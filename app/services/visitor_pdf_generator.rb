# frozen_string_literal: true

# app/services/visitor_pdf_generator.rb
class VisitorPdfGenerator
  # Color Palette
  HAITI_BLUE = "00209F"
  HAITI_RED = "D52B1E"
  TEXT_DARK = "1A202C"
  TEXT_MUTED = "718096"
  SUCCESS_GREEN = "1A936F"
  WARNING_ORANGE = "ED8936"
  BACKGROUND_LIGHT = "F7FAFC"

  def initialize(visitor)
    @visitor = visitor
  end

  def generate
    logo_path = Rails.root.join("app/assets/images/Haiti_flag.png")

    Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 40, 40 ]) do |pdf|
      configure_fonts(pdf)

      render_header(pdf, logo_path)
      render_photo_section(pdf)
      render_visitor_info(pdf)
      render_qr_section(pdf)
      render_footer(pdf)
      render_watermark(pdf)
    end.render
  end

  private

  # =========================================================
  # Font Configuration
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
  # Header Section
  # =========================================================

  def render_header(pdf, logo_path)
    # Logo
    if File.exist?(logo_path)
      pdf.image logo_path.to_s, width: 80, position: :center
      pdf.move_down 10
    end

    # Full name
    full_name = [ @visitor.title, @visitor.first_name, @visitor.middle_name, @visitor.last_name ]
                  .compact.join(" ").squish

    pdf.font "Montserrat", style: :bold, size: 20
    pdf.fill_color TEXT_DARK
    pdf.text full_name, align: :center

    pdf.move_down 5

    # Document title
    pdf.font "Montserrat", style: :bold, size: 16
    pdf.fill_color HAITI_BLUE
    pdf.text "BonTouris ID Certificate", align: :center

    pdf.move_down 3
    pdf.font "Inter", size: 9
    pdf.fill_color TEXT_MUTED
    pdf.text "Republic of Haiti - Visitor Identity Document", align: :center

    pdf.move_down 15
    pdf.stroke_color TEXT_MUTED
    pdf.stroke_horizontal_rule
    pdf.move_down 20
  end

  # =========================================================
  # Photo Section
  # =========================================================

  def render_photo_section(pdf)
    photo_width = 120

    if @visitor.selfie.attached?
      Tempfile.open([ "visitor_selfie_#{@visitor.id}", ".jpg" ]) do |tmp|
        tmp.binmode
        tmp.write(@visitor.selfie.download)
        tmp.rewind
        pdf.image tmp.path, width: photo_width, position: :center
      end
    else
      # Photo placeholder
      x_center = (pdf.bounds.width - photo_width) / 2
      pdf.bounding_box([ x_center, pdf.cursor ], width: photo_width, height: photo_width * 1.2) do
        pdf.stroke_color TEXT_MUTED
        pdf.dash(2, space: 2)
        pdf.stroke_bounds
        pdf.undash

        pdf.fill_color TEXT_MUTED
        pdf.font "Inter", size: 10
        pdf.text_box "No photo available",
                     at: [ 0, photo_width * 0.6 ],
                     width: photo_width,
                     align: :center
      end
    end

    pdf.move_down 25
  end

  # =========================================================
  # Visitor Information
  # =========================================================

  def render_visitor_info(pdf)
    pdf.font "Inter", size: 11
    pdf.fill_color TEXT_DARK

    # BonTouris ID
    pdf.font "Inter", style: :bold
    pdf.text "BonTouris ID: #{@visitor.bonid}", align: :center
    pdf.move_down 15

    # Info rows
    info_rows = [
      [ "Nationality", @visitor.nationality ],
      [ "Purpose of Visit", @visitor.purpose_of_visit ],
      [ "Expected Stay", "#{@visitor.stay_duration_days} days" ],
      [ "Port of Entry", @visitor.port_of_entry ]
    ]

    info_rows.each do |label, value|
      render_info_row(pdf, label, value)
    end

    # Validity (highlighted)
    pdf.move_down 10
    pdf.fill_color HAITI_RED
    pdf.font "Inter", style: :bold, size: 12
    pdf.text "Valid Until: #{@visitor.expires_at.strftime('%B %d, %Y')}", align: :center
    pdf.fill_color TEXT_DARK
    pdf.move_down 15

    # Address (if exists)
    if @visitor.address
      pdf.font "Inter", style: :bold, size: 10
      pdf.fill_color TEXT_MUTED
      pdf.text "ADDRESS IN HAITI", align: :center
      pdf.move_down 5

      pdf.font "Inter", size: 10
      pdf.fill_color TEXT_DARK
      pdf.text @visitor.address.formatted_haiti_display, align: :center, leading: 3
      pdf.move_down 15
    end

    # Emergency Contact (if exists)
    if @visitor.local_contact
      contact = @visitor.local_contact

      pdf.font "Inter", style: :bold, size: 10
      pdf.fill_color TEXT_MUTED
      pdf.text "EMERGENCY CONTACT", align: :center
      pdf.move_down 5

      pdf.font "Inter", size: 10
      pdf.fill_color TEXT_DARK
      pdf.text "#{contact.name} - #{contact.phone}", align: :center

      if contact.verified?
        pdf.move_down 3
        pdf.fill_color SUCCESS_GREEN
        pdf.font "Inter", style: :bold, size: 9
        pdf.text "[VERIFIED BONID CONTACT]", align: :center

        if contact.bonid.present?
          pdf.move_down 2
          pdf.font "Inter", size: 8
          pdf.fill_color TEXT_MUTED
          pdf.text "BonID: #{contact.bonid}", align: :center
        end

        pdf.fill_color TEXT_DARK
      else
        pdf.move_down 3
        pdf.fill_color WARNING_ORANGE
        pdf.font "Inter", style: :bold, size: 9
        pdf.text "[Unverified Contact]", align: :center
        pdf.fill_color TEXT_DARK
      end

      pdf.move_down 15
    end
  end

  def render_info_row(pdf, label, value)
    pdf.font "Inter", size: 9
    pdf.fill_color TEXT_MUTED
    pdf.text label.upcase, align: :center

    pdf.move_down 2
    pdf.font "Inter", style: :bold, size: 11
    pdf.fill_color TEXT_DARK
    pdf.text value, align: :center

    pdf.move_down 10
  end

  # =========================================================
  # QR Code Section
  # =========================================================

  def render_qr_section(pdf)
    return unless @visitor.visitor_qr_png_base64.present?

    pdf.move_down 10

    Tempfile.open([ "visitor_qr_#{@visitor.bonid}", ".png" ]) do |tmp|
      tmp.binmode
      tmp.write(Base64.decode64(@visitor.visitor_qr_png_base64))
      tmp.rewind
      pdf.image tmp.path, width: 150, position: :center
    end

    pdf.move_down 10
    pdf.font "Inter", size: 9
    pdf.fill_color TEXT_MUTED
    pdf.text "Scan to verify at Verifyem trusted partners", align: :center
    pdf.move_down 20
  end

  # =========================================================
  # Footer
  # =========================================================

  def render_footer(pdf)
    checksum = generate_checksum

    pdf.stroke_color TEXT_MUTED
    pdf.stroke_horizontal_rule
    pdf.move_down 10

    pdf.font "Inter", style: :bold, size: 8
    pdf.fill_color TEXT_MUTED
    pdf.text "OFFLINE VERIFICATION CODE", align: :center

    pdf.move_down 5
    pdf.font "Courier", size: 11
    pdf.fill_color HAITI_BLUE
    pdf.text checksum, align: :center, character_spacing: 1.5

    pdf.move_down 8
    pdf.font "Inter", size: 7
    pdf.fill_color TEXT_MUTED
    pdf.text "BonTouris ID - Powered by Verifyem - Republic of Haiti", align: :center
  end

  def generate_checksum
    secret = Rails.application.credentials.hmac_secret || "bonid-fallback"
    OpenSSL::HMAC.hexdigest("SHA256", secret, @visitor.bonid)[-8..].upcase
  end

  # =========================================================
  # Watermark
  # =========================================================

  def render_watermark(pdf)
    pdf.canvas do
      pdf.save_graphics_state do
        pdf.fill_color "DDDDDD"
        pdf.transparent(0.2) do
          pdf.rotate(45, origin: [ pdf.bounds.width / 2, pdf.bounds.height / 2 ]) do
            pdf.font("Montserrat", style: :bold, size: 42) do
              pdf.text_box(
                "PRIVATE DOCUMENT",
                at: [ 0, pdf.bounds.height / 2 + 15 ],
                width: pdf.bounds.width,
                height: 80,
                align: :center,
                valign: :center
              )
            end

            pdf.font("Inter", size: 20) do
              pdf.text_box(
                "DO NOT SHARE - VERIFYEM",
                at: [ 0, pdf.bounds.height / 2 - 50 ],
                width: pdf.bounds.width,
                height: 50,
                align: :center,
                valign: :center
              )
            end
          end
        end
      end
    end
  end
end
