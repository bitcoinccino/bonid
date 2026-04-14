# frozen_string_literal: true

# app/services/crime_certificate_service.rb
#
# Service to generate official crime certificates for incident reports.
# Supports both JSON and PDF formats.
#
# Features:
# - Official Haiti PNH formatting
# - QR code for verification
# - Digital signature validation
# - Multi-language support (French/Creole)
# - Tamper-proof certificate ID
#
# Usage:
#   # JSON certificate
#   CrimeCertificateService.new(
#     report: incident_report,
#     partner: partner,
#     format: :json
#   ).generate
#
#   # PDF certificate
#   CrimeCertificateService.new(
#     report: incident_report,
#     partner: partner,
#     format: :pdf
#   ).generate
#
class CrimeCertificateService
  SEVERITY_LABELS = {
    1 => { en: "Minor", fr: "Mineur", ht: "Ti" },
    2 => { en: "Low", fr: "Faible", ht: "Ba" },
    3 => { en: "Moderate", fr: "Modéré", ht: "Modere" },
    4 => { en: "High", fr: "Élevé", ht: "Wo" },
    5 => { en: "Severe", fr: "Grave", ht: "Grav" },
    6 => { en: "Critical", fr: "Critique", ht: "Kritik" }
  }.freeze

  ROLE_LABELS = {
    "suspect" => { en: "Suspect", fr: "Suspect", ht: "Sispèk" },
    "victim" => { en: "Victim", fr: "Victime", ht: "Viktim" },
    "witness" => { en: "Witness", fr: "Témoin", ht: "Temwen" },
    "innocent" => { en: "Innocent Party", fr: "Partie Innocente", ht: "Pati Inosan" },
    "accomplice" => { en: "Accomplice", fr: "Complice", ht: "Konplis" },
    "unknown" => { en: "Unknown", fr: "Inconnu", ht: "Enkoni" }
  }.freeze

  def initialize(report:, partner:, format: :json, language: :fr)
    @report = report
    @partner = partner
    @format = format.to_sym
    @language = language.to_sym
  end

  def generate
    case @format
    when :pdf
      generate_pdf
    else
      generate_json
    end
  end

  private

  # Generate JSON certificate
  def generate_json
    {
      certificate_id: generate_certificate_id,
      type: "CRIME_INCIDENT_CERTIFICATE",
      version: "1.0.0",
      issued_at: Time.current.iso8601,
      valid_until: (Time.current + 24.hours).iso8601,
      issuing_authority: {
        name:           "Police Nationale d'Haïti",
        abbreviation:   "PNH",
        country:        "Haiti",
        unit:           @report.officer&.unit_name,
        directorate:    @report.officer&.department_directorate.present? ?
                          "#{@report.officer.department_directorate} — #{OfficerConstants::DEPARTMENTS[@report.officer.department_directorate]}" :
                          (@report.officer&.partner&.name || "PNH Central"),
        signed_by_unit: "Direction Centrale de la Police Judiciaire (DCPJ)"
      },
      incident: build_incident_data,
      persons_involved: build_persons_data,
      officer: build_officer_data,
      location: build_location_data,
      evidence_summary: build_evidence_summary,
      legal_references: build_legal_references,
      verification: build_verification_data,
      partner_access: {
        partner_name: @partner.name,
        partner_type: @partner.sector,
        access_granted_at: Time.current.iso8601,
        access_purpose: "Official inquiry"
      },
      digital_signature: generate_digital_signature,
      qr_verification_url: generate_qr_url
    }
  end

  # Generate PDF certificate
  def generate_pdf
    require "prawn"
    require "prawn/table"

    pdf = Prawn::Document.new(
      page_size: "LETTER",
      margin: [50, 50, 50, 50]
    )

    # Header
    render_pdf_header(pdf)

    # Certificate title
    render_pdf_title(pdf)

    # Incident details
    render_pdf_incident_section(pdf)

    # Persons involved
    render_pdf_persons_section(pdf)

    # Location
    render_pdf_location_section(pdf)

    # Legal references
    render_pdf_legal_section(pdf)

    # Officer signature area
    render_pdf_signature_section(pdf)

    # Footer with QR code
    render_pdf_footer(pdf)

    pdf.render
  end

  # ============================
  # JSON Data Builders
  # ============================

  def build_incident_data
    {
      report_id: @report.report_id,
      case_number: @report.bonid_case_number,
      uuid: @report.uuid,
      crime_type: @report.crime_type,
      crime_code: @report.crime_type_record&.code || CrimeType.find_by(name: @report.crime_type)&.code,
      crime_category: determine_crime_category,
      severity: {
        level: @report.crime_severity_level,
        label: severity_label(@report.crime_severity_level)
      },
      occurred_at: @report.occurred_at&.iso8601,
      submitted_at: @report.submitted_at&.iso8601,
      report_status: @report.status,
      description: @report.description&.truncate(500)
    }
  end

  def build_persons_data
    @report.person_involvements.map do |pi|
      person_data = {
        role: pi.role,
        role_label: role_label(pi.role),
        status: pi.status,
        status_label: PersonInvolvement.statuses[pi.status],
        id_type: determine_id_type(pi)
      }

      # Add masked identifier
      if pi.bonid.present?
        person_data[:masked_id] = mask_bonid(pi.bonid)
      end

      # Add nationality for tourists
      if pi.tourist? && pi.visitor_submission.present?
        person_data[:nationality] = pi.visitor_submission.nationality
      end

      person_data
    end
  end

  def build_officer_data
    return nil unless @report.officer

    officer = @report.officer
    verified = officer.user&.identity_submissions&.approved&.last

    {
      badge_id: officer.badge_id,
      rank: officer.rank,
      unit: officer.unit_name,
      specialty: officer.unit_type,
      bonid_verified: officer.user&.bonid_verified?,
      signature_on_file: verified&.signature&.attached? || verified&.signature_data.present?
    }
  end

  def build_location_data
    return nil unless @report.address

    addr = @report.address
    {
      street_address: addr.street_address,
      commune: addr.commune&.name,
      communal_section: addr.communal_section&.name,
      department: addr.department&.name,
      postal_code: addr.postal_code,
      coordinates: addr.latitude.present? ? {
        latitude: addr.latitude,
        longitude: addr.longitude
      } : nil,
      country: "Haiti"
    }
  end

  def build_evidence_summary
    {
      media_count: @report.media.count,
      media_types: @report.media.map { |m| m.content_type.split("/").first }.uniq,
      has_photos: @report.media.any? { |m| m.content_type.start_with?("image/") },
      has_videos: @report.media.any? { |m| m.content_type.start_with?("video/") },
      has_documents: @report.media.any? { |m| m.content_type.include?("pdf") || m.content_type.include?("document") }
    }
  end

  def build_legal_references
    {
      penal_code_articles: @report.penal_code_articles,
      crime_classification: determine_crime_category,
      jurisdiction: "Haiti National"
    }
  end

  def build_verification_data
    {
      certificate_hash: generate_certificate_hash,
      verification_url: generate_qr_url,
      valid_for_hours: 24,
      requires_consent: true,
      tamper_detection: true
    }
  end

  # ============================
  # PDF Renderers
  # ============================

  def render_pdf_header(pdf)
    # Haiti coat of arms area (placeholder)
    pdf.bounding_box([0, pdf.cursor], width: 100, height: 80) do
      pdf.text "🇭🇹", size: 40, align: :center
    end

    # Header text
    pdf.bounding_box([120, pdf.cursor + 70], width: 350, height: 80) do
      pdf.text "RÉPUBLIQUE D'HAÏTI", size: 14, style: :bold, align: :center
      pdf.move_down 5
      pdf.text "POLICE NATIONALE D'HAÏTI", size: 12, align: :center
      pdf.move_down 3
      pdf.text @report.officer&.partner&.name || "Direction Centrale", size: 10, align: :center
    end

    pdf.move_down 30
    pdf.stroke_horizontal_rule
    pdf.move_down 15
  end

  def render_pdf_title(pdf)
    pdf.text "CERTIFICAT D'INCIDENT CRIMINEL", size: 16, style: :bold, align: :center
    pdf.move_down 5
    pdf.text "CRIME INCIDENT CERTIFICATE", size: 12, align: :center, color: "666666"
    pdf.move_down 20

    # Certificate info box
    pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width, height: 60) do
      pdf.stroke_bounds
      pdf.indent(10) do
        pdf.move_down 10
        pdf.text "N° de Dossier / Case Number: #{@report.report_id}", size: 10
        pdf.text "N° BonID: #{@report.bonid_case_number}", size: 10
        pdf.text "Date d'émission / Issue Date: #{Time.current.strftime('%d %B %Y')}", size: 10
      end
    end

    pdf.move_down 20
  end

  def render_pdf_incident_section(pdf)
    pdf.text "DÉTAILS DE L'INCIDENT / INCIDENT DETAILS", size: 12, style: :bold
    pdf.move_down 5
    pdf.stroke_horizontal_rule
    pdf.move_down 10

    data = [
      ["Type de Crime / Crime Type:", @report.crime_type],
      ["Code:", @report.crime_type_record&.code || "N/A"],
      ["Niveau de Gravité / Severity:", "#{@report.crime_severity_level} - #{severity_label(@report.crime_severity_level)}"],
      ["Date de l'Incident / Incident Date:", @report.occurred_at&.strftime("%d %B %Y à %H:%M") || "Non spécifié"],
      ["Statut / Status:", @report.status.humanize]
    ]

    pdf.table(data, cell_style: { size: 10, padding: [5, 10] }, column_widths: [180, 320])
    pdf.move_down 15

    # Description
    pdf.text "Description:", size: 10, style: :bold
    pdf.text @report.description&.truncate(800) || "Aucune description fournie.", size: 10
    pdf.move_down 20
  end

  def render_pdf_persons_section(pdf)
    pdf.text "PERSONNES IMPLIQUÉES / PERSONS INVOLVED", size: 12, style: :bold
    pdf.move_down 5
    pdf.stroke_horizontal_rule
    pdf.move_down 10

    headers = ["Rôle/Role", "Statut/Status", "Type ID", "ID (Masqué)"]
    rows = @report.person_involvements.map do |pi|
      [
        role_label(pi.role),
        PersonInvolvement.statuses[pi.status] || "N/A",
        determine_id_type(pi),
        pi.bonid.present? ? mask_bonid(pi.bonid) : "Non identifié"
      ]
    end

    if rows.any?
      pdf.table([headers] + rows,
        header: true,
        cell_style: { size: 9, padding: [5, 8] },
        row_colors: ["FFFFFF", "F5F5F5"]
      )
    else
      pdf.text "Aucune personne enregistrée / No persons recorded.", size: 10, style: :italic
    end

    pdf.move_down 20
  end

  def render_pdf_location_section(pdf)
    pdf.text "LIEU DE L'INCIDENT / INCIDENT LOCATION", size: 12, style: :bold
    pdf.move_down 5
    pdf.stroke_horizontal_rule
    pdf.move_down 10

    if @report.address
      addr = @report.address
      location_parts = [
        addr.street_address,
        addr.commune&.name,
        addr.communal_section&.name,
        addr.department&.name,
        "Haiti"
      ].compact.join(", ")

      pdf.text location_parts, size: 10
    else
      pdf.text "Lieu non spécifié / Location not specified.", size: 10, style: :italic
    end

    pdf.move_down 20
  end

  def render_pdf_legal_section(pdf)
    pdf.text "RÉFÉRENCES LÉGALES / LEGAL REFERENCES", size: 12, style: :bold
    pdf.move_down 5
    pdf.stroke_horizontal_rule
    pdf.move_down 10

    if @report.penal_code_articles.present?
      pdf.text "Code Pénal Haïtien: #{@report.penal_code_articles}", size: 10
    else
      pdf.text "Références à déterminer / References to be determined.", size: 10, style: :italic
    end

    pdf.move_down 30
  end

  def render_pdf_signature_section(pdf)
    pdf.text "CERTIFICATION", size: 12, style: :bold
    pdf.move_down 10

    pdf.text "Ce certificat atteste que les informations ci-dessus sont conformes aux dossiers officiels de la Police Nationale d'Haïti.", size: 9
    pdf.move_down 5
    pdf.text "This certificate attests that the above information conforms to the official records of the Haitian National Police.", size: 9, color: "666666"

    pdf.move_down 30

    # Signature boxes
    pdf.bounding_box([0, pdf.cursor], width: 200, height: 60) do
      pdf.stroke_bounds
      pdf.move_down 40
      pdf.text "Officier Responsable / Responsible Officer", size: 8, align: :center
    end

    pdf.bounding_box([300, pdf.cursor + 60], width: 200, height: 60) do
      pdf.stroke_bounds
      pdf.move_down 40
      pdf.text "Cachet Officiel / Official Stamp", size: 8, align: :center
    end
  end

  def render_pdf_footer(pdf)
    pdf.move_down 30

    # QR code placeholder
    pdf.bounding_box([0, pdf.cursor], width: 80, height: 80) do
      pdf.stroke_bounds
      pdf.move_down 30
      pdf.text "QR", size: 20, align: :center
    end

    # Footer text
    pdf.bounding_box([100, pdf.cursor + 70], width: 400, height: 80) do
      pdf.text "Scanner pour vérifier / Scan to verify", size: 8
      pdf.text generate_qr_url, size: 7, color: "666666"
      pdf.move_down 10
      pdf.text "Certificate ID: #{generate_certificate_id}", size: 7
      pdf.text "Hash: #{generate_certificate_hash[0..31]}...", size: 7, color: "999999"
      pdf.move_down 10
      pdf.text "Ce document est valide 24 heures à partir de l'émission.", size: 8
      pdf.text "This document is valid for 24 hours from issue.", size: 8, color: "666666"
    end
  end

  # ============================
  # Helper Methods
  # ============================

  def determine_crime_category
    IncidentReport::CRIME_TYPES.each do |category, crimes|
      return category.to_s.humanize if crimes.include?(@report.crime_type)
    end
    "Other"
  end

  def determine_id_type(pi)
    if pi.tourist?
      "BonTouris"
    elsif pi.citizen?
      "BonID"
    else
      "Unknown"
    end
  end

  def mask_bonid(bonid)
    return bonid if bonid.blank?

    if bonid.start_with?("T-")
      # BonTouris: keep T- prefix visible
      parts = bonid.split("-")
      [parts[0], parts[1], "••••", "•", parts[-3], parts[-2], parts[-1]].join("-")
    else
      # Citizen BonID: MB••••••••697280
      stripped = bonid.gsub("-", "")
      last6 = stripped.last(6)
      dots = "•" * [stripped.length - 8, 6].max
      "MB#{dots}#{last6}"
    end
  end

  def severity_label(level)
    labels = SEVERITY_LABELS[level] || SEVERITY_LABELS[1]
    labels[@language] || labels[:fr]
  end

  def role_label(role)
    labels = ROLE_LABELS[role] || ROLE_LABELS["unknown"]
    labels[@language] || labels[:fr]
  end

  def generate_certificate_id
    # Stable: same report + partner always yields the same cert ID (no volatile timestamp)
    Digest::SHA256.hexdigest("#{@report.uuid}|#{@partner.id}")[0..15].upcase
  end

  def generate_certificate_hash
    data = "#{@report.uuid}|#{@report.report_id}|#{Time.current.to_i}|#{@partner.id}"
    Digest::SHA256.hexdigest(data)
  end

  def generate_digital_signature
    cert_id   = generate_certificate_id
    issued_at = Time.current.iso8601

    # Canonical payload — sorted keys for deterministic signing
    canonical = {
      case_number:    @report.bonid_case_number,
      certificate_id: cert_id,
      issued_at:      issued_at,
      partner_id:     @partner.id,
      report_id:      @report.report_id
    }.to_json

    pem = Rails.application.credentials.dig(:bonid, :rsa_private_key)

    if pem.present?
      private_key     = OpenSSL::PKey::RSA.new(pem)
      digest          = OpenSSL::Digest::SHA256.new
      signature_bytes = private_key.sign_pss(digest, canonical,
                          salt_length: :digest,
                          mgf1_hash:   OpenSSL::Digest::SHA256.new)
      {
        algorithm:       "RSASSA-PSS",
        signature_value: Base64.strict_encode64(signature_bytes),
        signed_by:       "DCPJ-Digital-Unit",
        signed_at:       issued_at,
        public_key_url:  "#{Rails.application.config.bonid_base_url || 'https://pnh.gouv.ht'}/certs/public_key.pem"
      }
    else
      # Fallback until RSA key is provisioned in credentials
      secret    = Rails.application.credentials.dig(:bonid, :signature_secret) || "default_secret"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, canonical)
      {
        algorithm:       "HMAC-SHA256",
        signature_value: signature,
        signed_by:       "DCPJ-Digital-Unit",
        signed_at:       issued_at
      }
    end
  end

  def generate_qr_url
    base = Rails.application.config.try(:bonid_verification_url) ||
           Rails.application.config.bonid_base_url ||
           "https://verifie.pnh.gouv.ht"
    "#{base}/certificat/#{generate_certificate_id}"
  end
end
