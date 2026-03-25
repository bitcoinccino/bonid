# app/models/officer_complaint.rb
#
# OfficerComplaint — Legal complaint filed by a citizen (BonID), tourist (BonTouris),
# or anonymous person against a PNH officer. Routed to the correct IGPNH directorate.
#
# Six pillars:
#   1. Complainant Information (identity pre-filled from BonID/BonTouris session)
#   2. Incident Details       (when, where, which PNH unit)
#   3. Officer Identification (badge, name, vehicle, or physical description)
#   4. Nature of Allegations  (category + specific misconduct from OfficerConstants)
#   5. Evidence & Narrative   (statement of facts, file uploads, witnesses)
#   6. Digital Proof          (tracking number, routing, status workflow)

class OfficerComplaint < ApplicationRecord
  include OfficerConstants

  # === Active Storage (Pillar 5 — photos, videos, medical reports) ===
  has_many_attached :evidences

  # === Associations ===
  belongs_to :user,               optional: true  # Citizen (BonID holder)
  belongs_to :visitor_submission, optional: true  # Tourist (BonTouris holder)

  # Accused officer — optional (citizen may not know badge/name)
  belongs_to :accused_officer, class_name: "Officer", optional: true,
             foreign_key: :accused_officer_id

  # Geographic hierarchy of the incident location
  belongs_to :department,       optional: true
  belongs_to :arrondissement,   optional: true
  belongs_to :commune,          optional: true
  belongs_to :communal_section, optional: true

  # IGPNH investigator assigned to this case
  belongs_to :assigned_to, class_name: "Officer", optional: true,
             foreign_key: :assigned_to_id

  # === Enums ===
  enum :status, {
    submitted:              "submitted",
    under_review:           "under_review",
    investigation_open:     "investigation_open",
    disciplinary_action:    "disciplinary_action",
    referred_to_prosecutor: "referred_to_prosecutor",
    closed_sustained:       "closed_sustained",    # Complaint upheld
    closed_unsustained:     "closed_unsustained"   # Dismissed / insufficient evidence
  }, default: :submitted

  enum :complainant_role, {
    victim:    "victim",
    witness:   "witness",
    relative:  "relative",   # Filing on behalf of a victim (family)
    legal_rep: "legal_rep"   # Attorney or OPC representative
  }

  enum :complainant_type, {
    citizen:   "citizen",    # Haitian citizen with verified BonID
    tourist:   "tourist",    # Foreign national with BonTouris
    officer:   "officer",    # Another PNH officer filing internally
    anonymous: "anonymous"   # No identity provided — logged but limited prosecution
  }

  # === Pillar 1 Validations: Complainant Information ===
  validates :complainant_name,  presence: true, unless: :anonymous?
  validates :complainant_bonid, presence: true, unless: :anonymous?
  validates :complainant_phone, presence: true, unless: :anonymous?
  validates :complainant_role,  presence: true
  validates :complainant_type,  presence: true

  # === Pillar 2 Validations: Incident Details ===
  validates :occurred_at,          presence: true
  validates :location_description, presence: true
  validates :department_id,        presence: { message: "Selecting the department where the incident occurred is required for routing." }

  # === Pillar 3 Validation: Officer Identification ===
  # At least one identifier required — badge, name, vehicle, or physical description
  validate :officer_identification_present

  # === Pillar 4 Validations: Allegations ===
  validates :allegation_category, presence: true,
    inclusion: { in: OfficerConstants::COMPLAINT_TYPES.keys,
                 message: "is not a recognized misconduct category." }
  validates :specific_allegation, presence: true

  # === Pillar 5 Validations: Narrative ===
  validates :narrative, presence: true,
    length: { minimum: 50, message: "must be at least 50 characters — please describe what happened in detail." }

  validates :uuid,            presence: true, uniqueness: true
  validates :tracking_number, presence: true, uniqueness: true

  # === Callbacks ===
  before_validation :generate_uuid,          on: :create
  before_validation :generate_tracking_number, on: :create
  before_validation :auto_resolve_accused_officer
  before_validation :auto_assign_directorate
  before_create     :set_submitted_at
  after_create      :sign_certificate!
  after_create      :notify_igpnh
  after_create      :notify_witnesses

  # === Scopes ===
  scope :pending_review,  -> { where(status: %w[submitted under_review]) }
  scope :active,          -> { where(status: "investigation_open") }
  scope :by_directorate,  ->(dir) { where(routed_directorate: dir) }
  scope :recent,          -> { order(created_at: :desc) }
  scope :for_citizen,     ->(bonid) { where(complainant_bonid: bonid) }

  # === Public Instance Methods ===

  def anonymous?
    complainant_type == "anonymous"
  end

  def tourist?
    complainant_type == "tourist"
  end

  # Human-readable reference for the citizen's proof of filing
  def certificate_reference
    "IGPNH-#{tracking_number}"
  end

  # ── Anti-tamper: cryptographic certificate integrity ──────────────────────
  #
  # The signature is an HMAC-SHA256 of the five fields that appear on the
  # printed certificate:
  #   tracking_number | complainant_bonid | allegation_category |
  #   specific_allegation | occurred_at(ISO8601) | department_id
  #
  # If ANY of those fields is altered in the database the signature will no
  # longer match and `certificate_valid?` returns false.
  # Officers verifying the printed QR hit /verify/:tracking_number which
  # compares the stored signature against a freshly-computed one.

  # Compact, URL-safe hex digest (first 16 bytes = 32 hex chars) printed on
  # the certificate so a human can spot-check without a scanner.
  CERTIFICATE_SIG_PREFIX = "IGPNH-SIG-".freeze

  def compute_certificate_signature
    secret = Rails.application.credentials.dig(:bonid, :certificate_secret) ||
             Rails.application.credentials.secret_key_base
    payload = [
      tracking_number,
      complainant_bonid.to_s.upcase,
      allegation_category,
      specific_allegation,
      occurred_at&.utc&.iso8601,
      department_id.to_s
    ].join("|")
    OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
  end

  def certificate_valid?
    certificate_signature.present? &&
      ActiveSupport::SecurityUtils.secure_compare(
        certificate_signature,
        compute_certificate_signature
      )
  end

  # Short 8-char human-readable checksum printed beneath the QR code
  def certificate_checksum
    certificate_signature.to_s.first(8).upcase
  end

  # Public URL embedded in the certificate QR code
  def verification_url
    "https://bonid.ht/complaints/verify/#{tracking_number}"
  end

  # Base64 PNG of the QR code pointing to the public verify URL
  # Returns nil if rqrcode is not available
  def certificate_qr_png_base64
    return @_cert_qr if defined?(@_cert_qr)
    @_cert_qr = begin
      qr  = RQRCode::QRCode.new(verification_url, level: :h)
      png = qr.as_png(size: 180, border_modules: 2)
      Base64.strict_encode64(png.to_s)
    rescue => e
      Rails.logger.warn("[OfficerComplaint] QR generation failed for #{tracking_number}: #{e.message}")
      nil
    end
  end

  # Full directorate name for display
  def routing_directorate_name
    OfficerConstants::DEPARTMENTS[routed_directorate] ||
      "IGPNH — Inspection Générale de la PNH"
  end

  # Witnesses stored as JSON array of {name, phone, email, bonid, relation, id_type}
  def witnesses_list
    (witnesses || []).map(&:with_indifferent_access)
  end

  def status_label
    {
      "submitted"              => "Soumis",
      "under_review"           => "En cours d'examen",
      "investigation_open"     => "Enquête ouverte",
      "disciplinary_action"    => "Sanction administrative",
      "referred_to_prosecutor" => "Référé au Parquet",
      "closed_sustained"       => "Classé — Plainte retenue",
      "closed_unsustained"     => "Classé sans suite"
    }[status] || status.humanize
  end

  def status_color
    {
      "submitted"              => "warning",
      "under_review"           => "info",
      "investigation_open"     => "primary",
      "disciplinary_action"    => "danger",
      "referred_to_prosecutor" => "dark",
      "closed_sustained"       => "success",
      "closed_unsustained"     => "secondary"
    }[status] || "secondary"
  end

  # Compute and persist the certificate HMAC signature.
  # Called after_create and also available for backfilling old records.
  def sign_certificate!
    sig = compute_certificate_signature
    update_columns(
      certificate_signature: sig,
      certificate_signed_at: Time.current
    )
  rescue => e
    Rails.logger.error("[OfficerComplaint] sign_certificate! failed for #{tracking_number}: #{e.message}")
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def generate_tracking_number
    return if tracking_number.present?
    loop do
      candidate = "#{Time.current.year}-#{SecureRandom.alphanumeric(6).upcase}"
      unless OfficerComplaint.exists?(tracking_number: candidate)
        self.tracking_number = candidate
        break
      end
    end
  end

  # If citizen provided a badge ID or name, try to match against Officer records
  def auto_resolve_accused_officer
    return if accused_officer_id.present?
    if accused_officer_badge.present?
      self.accused_officer_id = Officer.find_by(badge_id: accused_officer_badge)&.id
    elsif accused_officer_name.present?
      # Fuzzy name match — last name match is enough for routing
      parts = accused_officer_name.to_s.split
      if parts.any?
        officer = Officer.where("last_name ILIKE ?", "%#{parts.last}%").first
        self.accused_officer_id = officer&.id
      end
    end
  end

  # Auto-set the routing directorate from the accused officer or incident department
  def auto_assign_directorate
    return if routed_directorate.present?

    # Prefer accused officer's directorate for accurate internal routing
    if accused_officer_id.present?
      officer = accused_officer || Officer.find_by(id: accused_officer_id)
      self.routed_directorate = officer&.department_directorate
    end

    # Fall back to the department of the incident (mapped to IGPNH regional office)
    if routed_directorate.blank? && department.present?
      self.routed_directorate = department_to_directorate(department.name)
    end

    # Final fallback — Port-au-Prince IGPNH HQ
    self.routed_directorate ||= "DDO"
  end

  def set_submitted_at
    self.submitted_at ||= Time.current
  end

  def officer_identification_present
    if accused_officer_badge.blank? &&
       accused_officer_name.blank? &&
       accused_officer_vehicle.blank? &&
       physical_description.blank? &&
       accused_officer_unit.blank?
      errors.add(:base,
        "Ou dwe bay omwen yon fason pou idantifye polisye a: " \
        "non, nimewo badj, nimewo machin, inite, oswa deskripsyon fizik.")
    end
  end

  # Map geographic department names to PNH directorate codes
  DEPARTMENT_TO_DIRECTORATE = {
    "Ouest"      => "DDO",
    "Nord"       => "DDN",
    "Sud"        => "DDS",
    "Artibonite" => "DDA",
    "Nord-Est"   => "DDNE",
    "Nord-Ouest" => "DDNO",
    "Sud-Est"    => "DDSE",
    "Centre"     => "DDC",
    "Grand'Anse" => "DDGA",
    "Nippes"     => "DDNIP"
  }.freeze

  def department_to_directorate(dept_name)
    DEPARTMENT_TO_DIRECTORATE.find { |k, _| dept_name.to_s.include?(k) }&.last
  end

  # Trigger background job to alert IGPNH dashboard
  def notify_igpnh
    IgpnhAlertJob.perform_later(id) if defined?(IgpnhAlertJob)
    Rails.logger.info("[OfficerComplaint] #{certificate_reference} submitted → routed to #{routed_directorate}")
  end

  # Send a confirmation email to each cited witness who has a verified email.
  # Each witness was auto-filled from a verified BonID or BonTouris record.
  def notify_witnesses
    witnesses_list.each do |witness|
      next if witness["email"].blank?

      OfficerComplaintMailer
        .with(complaint: self, witness: witness)
        .witness_cited
        .deliver_later

      Rails.logger.info(
        "[OfficerComplaint] Witness notification queued → #{witness['email']} (#{witness['bonid']})"
      )
    rescue => e
      Rails.logger.error(
        "[OfficerComplaint] Failed to queue witness notification for #{witness['email']}: #{e.message}"
      )
    end
  end
end
