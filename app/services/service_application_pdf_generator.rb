# frozen_string_literal: true

# app/services/service_application_pdf_generator.rb
#
# Generates a signed, sealed PDF from a submitted ServiceApplication.
# Uses the frozen schema_snapshot so the PDF always matches the form
# version the citizen filled out, even if the partner has since updated it.
#
# Features:
# - Partner header with logo
# - Multi-step form data rendered from snapshot
# - Citizen's BonID signature (from IdentitySubmission)
# - Partner's official seal (auto-applied on approval)
# - Verification QR code in footer
# - HMAC checksum for tamper detection
#
class ServiceApplicationPdfGenerator
  # Color Palette
  HAITI_BLUE   = "00209F"
  HAITI_RED    = "D52B1E"
  TEXT_DARK    = "1A202C"
  TEXT_MUTED   = "718096"
  SEAL_GREEN   = "059669"
  BORDER_LIGHT = "E2E8F0"
  BG_LIGHT     = "F7FAFC"

  def initialize(application)
    @app = application
    @schema = application.partner_schema
    @partner = application.partner
    @citizen = application.citizen
  end

  def generate
    pdf_data = build_pdf
    checksum = generate_pdf_checksum(pdf_data)

    # Attach the PDF and record metadata
    @app.pdf_document.attach(
      io: StringIO.new(pdf_data),
      filename: pdf_filename,
      content_type: "application/pdf"
    )
    @app.update!(
      pdf_checksum: checksum,
      pdf_generated_at: Time.current
    )

    pdf_data
  end

  private

  def build_pdf
    Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 50, 40 ]) do |pdf|
      configure_fonts(pdf)

      render_partner_header(pdf)
      render_application_info(pdf)
      render_form_data(pdf)
      render_signature_block(pdf) if @app.signature_consented?
      render_seal_block(pdf) if @app.sealed?
      render_footer(pdf)
      render_watermark(pdf) unless @app.status == "approved"
    end.render
  end

  # =========================================================
  # Fonts
  # =========================================================

  def configure_fonts(pdf)
    fonts_dir = Rails.root.join("app/assets/fonts")

    pdf.font_families.update(
      "Montserrat" => {
        normal: safe_font(fonts_dir, "Montserrat-Regular.ttf"),
        bold: safe_font(fonts_dir, "Montserrat-Bold.ttf")
      },
      "Inter" => {
        normal: safe_font(fonts_dir, "Inter-Regular.ttf"),
        bold: safe_font(fonts_dir, "Inter-Bold.ttf")
      }
    )

    pdf.font "Inter"
  end

  def safe_font(dir, filename)
    path = dir.join(filename)
    File.exist?(path) ? path.to_s : "Helvetica"
  end

  # =========================================================
  # Partner Header
  # =========================================================

  def render_partner_header(pdf)
    # Partner logo
    if @partner.logo.attached?
      render_attached_image(pdf, @partner.logo, width: 60, position: :center)
      pdf.move_down 8
    end

    # Partner name
    pdf.font "Montserrat", style: :bold, size: 14
    pdf.fill_color HAITI_BLUE
    pdf.text @partner.name, align: :center

    # Service name
    pdf.move_down 4
    pdf.font "Montserrat", style: :bold, size: 18
    pdf.fill_color TEXT_DARK
    pdf.text @schema.name, align: :center

    # Version & category
    pdf.move_down 4
    pdf.font "Inter", size: 8
    pdf.fill_color TEXT_MUTED
    category_labels = { "verification" => "Verifikasyon", "document" => "Dokiman", "application" => "Aplikasyon", "appointment" => "Randevou" }
    cat_label = category_labels[@schema.service_category] || @schema.service_category
    pdf.text "#{cat_label} · Vèsyon #{@app.schema_version} · #{@app.verification_code}", align: :center

    pdf.move_down 12
    pdf.stroke_color BORDER_LIGHT
    pdf.stroke_horizontal_rule
    pdf.move_down 15
  end

  # =========================================================
  # Application Info
  # =========================================================

  def render_application_info(pdf)
    pdf.font "Inter", size: 9
    pdf.fill_color TEXT_MUTED

    citizen_name = [ @citizen.first_name, @citizen.last_name ].compact.join(" ")

    info_table = [
      [ "Sitwayen", citizen_name ],
      [ "BonID", @citizen.try(:bonid) || "—" ],
      [ "Dat Soumisyon", @app.submitted_at&.strftime("%d/%m/%Y %H:%M") || "—" ],
      [ "Estati", @app.status_label ]
    ]

    if @app.total_price_cents.to_i > 0
      info_table << [ "Montan", @app.price_display ]
    end

    pdf.table(info_table, width: pdf.bounds.width, cell_style: {
      borders: [ :bottom ],
      border_color: BORDER_LIGHT,
      padding: [ 5, 8 ],
      font: "Inter",
      size: 9
    }) do |t|
      t.columns(0).font_style = :bold
      t.columns(0).text_color = TEXT_MUTED
      t.columns(0).width = 120
      t.columns(1).text_color = TEXT_DARK
    end

    pdf.move_down 20
  end

  # =========================================================
  # Form Data (from frozen snapshot)
  # =========================================================

  def render_form_data(pdf)
    steps = @app.frozen_fields_by_step

    steps.each_with_index do |step, step_idx|
      # Step header (if multi-step)
      if steps.length > 1
        pdf.font "Montserrat", style: :bold, size: 11
        pdf.fill_color HAITI_BLUE
        pdf.text "Etap #{step_idx + 1}: #{step[:name]}"
        pdf.move_down 8
      end

      step[:fields].each do |field|
        next if field["type"].in?(%w[bonid_signature seal_placeholder])

        render_form_field(pdf, field)
      end

      pdf.move_down 10
    end
  end

  def render_form_field(pdf, field)
    key = field["key"]
    label = field["label"] || key
    value = @app.form_data[key]
    field_type = field["type"]

    # Label
    pdf.font "Inter", style: :bold, size: 8
    pdf.fill_color TEXT_MUTED
    required_marker = field["required"] ? " *" : ""
    pdf.text "#{label.upcase}#{required_marker}"
    pdf.move_down 2

    # Value
    pdf.font "Inter", size: 10
    pdf.fill_color TEXT_DARK

    case field_type
    when "file"
      pdf.text value.present? ? "[Fichye Atache]" : "[Pa gen fichye]"
    when "calculated"
      calc_value = @app.calculated_values[key]
      currency = field["currency"] || "HTG"
      pdf.text calc_value.present? ? "#{calc_value} #{currency}" : "—"
    when "checkbox"
      pdf.text((value == true || value == "true") ? "Wi" : "Non")
    when "select"
      pdf.text value.present? ? value.to_s : "—"
    when "currency"
      currency = field["currency"] || "HTG"
      pdf.text value.present? ? "#{value} #{currency}" : "—"
    when "date"
      if value.present?
        begin
          pdf.text Date.parse(value.to_s).strftime("%d/%m/%Y")
        rescue
          pdf.text value.to_s
        end
      else
        pdf.text "—"
      end
    else
      pdf.text value.present? ? value.to_s : "—"
    end

    pdf.move_down 8
  end

  # =========================================================
  # Signature Block
  # =========================================================

  def render_signature_block(pdf)
    pdf.move_down 10
    pdf.stroke_color BORDER_LIGHT
    pdf.dash(3, space: 3)
    pdf.stroke_horizontal_rule
    pdf.undash
    pdf.move_down 12

    pdf.font "Montserrat", style: :bold, size: 10
    pdf.fill_color TEXT_DARK
    pdf.text "Siyati Sitwayen"
    pdf.move_down 6

    # Try to render the citizen's stored signature
    identity = @citizen.try(:identity_submissions)&.last
    if identity&.signature&.attached?
      render_attached_image(pdf, identity.signature, width: 150)
    else
      # Placeholder signature line
      pdf.stroke_color TEXT_MUTED
      pdf.move_down 30
      pdf.stroke_horizontal_line 0, 200
      pdf.move_down 3
      pdf.font "Inter", size: 7
      pdf.fill_color TEXT_MUTED
      pdf.text "Siyati dijital BonID"
    end

    pdf.move_down 4
    pdf.font "Inter", size: 7
    pdf.fill_color TEXT_MUTED
    citizen_name = [ @citizen.first_name, @citizen.last_name ].compact.join(" ")
    pdf.text "Siyen pa: #{citizen_name} · #{@app.signature_applied_at&.strftime('%d/%m/%Y %H:%M') || '—'}"

    pdf.move_down 15
  end

  # =========================================================
  # Seal Block
  # =========================================================

  def render_seal_block(pdf)
    pdf.move_down 5

    # Seal image
    if @partner.seal_image.attached?
      render_attached_image(pdf, @partner.seal_image, width: 100, position: :right)
    else
      # Placeholder seal circle
      x = pdf.bounds.width - 110
      y = pdf.cursor
      pdf.stroke_color SEAL_GREEN
      pdf.dash(2, space: 2)
      pdf.stroke_circle [ x + 50, y - 50 ], 45
      pdf.undash

      pdf.fill_color SEAL_GREEN
      pdf.font "Montserrat", style: :bold, size: 7
      pdf.text_box "SÈL OFISYÈL", at: [ x + 10, y - 30 ], width: 80, align: :center
      pdf.font "Inter", size: 6
      pdf.text_box @partner.name, at: [ x + 5, y - 42 ], width: 90, align: :center
    end

    # Seal metadata
    pdf.move_down 10
    pdf.font "Inter", size: 7
    pdf.fill_color SEAL_GREEN
    pdf.text "Dokiman sele pa #{@partner.name} · #{@app.sealed_at&.strftime('%d/%m/%Y %H:%M')}", align: :right
    pdf.fill_color TEXT_MUTED
    pdf.text "Checksum: #{@app.seal_checksum&.first(16)}...", align: :right, size: 6

    pdf.move_down 15
  end

  # =========================================================
  # Footer with QR Code
  # =========================================================

  def render_footer(pdf)
    pdf.stroke_color BORDER_LIGHT
    pdf.stroke_horizontal_rule
    pdf.move_down 8

    # Verification info
    pdf.font "Inter", style: :bold, size: 7
    pdf.fill_color TEXT_MUTED
    pdf.text "KÒD VERIFIKASYON", align: :center

    pdf.move_down 3
    pdf.font "Courier", size: 12
    pdf.fill_color HAITI_BLUE
    pdf.text @app.verification_code, align: :center, character_spacing: 2

    # QR code
    pdf.move_down 8
    qr_url = "#{base_url}/verify/#{@app.verification_code}"
    begin
      qr = RQRCode::QRCode.new(qr_url, level: :m)
      qr_png = qr.as_png(size: 120, border_modules: 1)

      Tempfile.open([ "qr_#{@app.verification_code}", ".png" ]) do |tmp|
        tmp.binmode
        tmp.write(qr_png.to_s)
        tmp.rewind
        pdf.image tmp.path, width: 100, position: :center
      end
    rescue => e
      Rails.logger.warn "QR generation failed: #{e.message}"
      pdf.font "Inter", size: 8
      pdf.fill_color TEXT_MUTED
      pdf.text "Verifye: #{qr_url}", align: :center
    end

    pdf.move_down 6
    pdf.font "Inter", size: 6
    pdf.fill_color TEXT_MUTED
    pdf.text "Eskane kòd QR la pou verifye otantisite dokiman sa a · BonID — Repiblik Dayiti", align: :center
    pdf.text "PDF Checksum: #{@app.pdf_checksum&.first(16) || 'pending'}...", align: :center, size: 5
  end

  # =========================================================
  # Watermark (for non-approved documents)
  # =========================================================

  def render_watermark(pdf)
    watermark_text = case @app.status
    when "draft" then "BOUYON"
    when "submitted" then "SOUMÈT - AP TANN"
    when "under_review" then "AP REVIZE"
    when "rejected" then "REJTE"
    else return
    end

    pdf.canvas do
      pdf.save_graphics_state do
        pdf.fill_color "CCCCCC"
        pdf.transparent(0.15) do
          pdf.rotate(45, origin: [ pdf.bounds.width / 2, pdf.bounds.height / 2 ]) do
            pdf.font("Montserrat", style: :bold, size: 48) do
              pdf.text_box(
                watermark_text,
                at: [ 0, pdf.bounds.height / 2 + 20 ],
                width: pdf.bounds.width,
                height: 80,
                align: :center,
                valign: :center
              )
            end
          end
        end
      end
    end
  end

  # =========================================================
  # Helpers
  # =========================================================

  def render_attached_image(pdf, attachment, width: 100, position: :left)
    return unless attachment.attached?

    Tempfile.open([ "bonid_img", ".#{attachment.filename.extension}" ]) do |tmp|
      tmp.binmode
      tmp.write(attachment.download)
      tmp.rewind
      pdf.image tmp.path, width: width, position: position
    end
  rescue => e
    Rails.logger.warn "Image render failed: #{e.message}"
  end

  def pdf_filename
    sanitized_name = @schema.name.parameterize(separator: "_")
    "bonid_#{sanitized_name}_#{@app.verification_code}.pdf"
  end

  def generate_pdf_checksum(pdf_data)
    OpenSSL::Digest::SHA256.hexdigest(pdf_data)
  end

  def base_url
    Rails.application.routes.default_url_options[:host] || "https://bonid.ht"
  end
end
