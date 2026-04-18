# frozen_string_literal: true

require "prawn"
require "prawn/measurement_extensions"
require "rqrcode"
require "chunky_png"

module Election
  # Renders a printable election-day accreditation badge as a single-page
  # PDF sized for a standard lanyard sleeve (100mm × 140mm portrait).
  #
  # OAS Recommendation (2015): accreditation badges MUST carry name, CIN,
  # photograph, accreditation code, and assigned station. Prior cycles
  # distributed generic un-personalized passes — this service closes that
  # door.
  #
  # Usage:
  #   bytes = Election::AccreditationBadgePdfService.call(accreditation: acc)
  #   send_data bytes, filename: "badj-MAN-XXXX.pdf", type: "application/pdf"
  class AccreditationBadgePdfService
    BADGE_WIDTH_MM  = 100
    BADGE_HEIGHT_MM = 140

    HAITI_BLUE   = "00209F"
    HAITI_RED    = "D52B1E"
    TEXT_DARK    = "1A202C"
    TEXT_MUTED   = "718096"
    BORDER_LIGHT = "E2E8F0"
    BG_LIGHT     = "F7FAFC"

    def self.call(accreditation:)
      new(accreditation).call
    end

    def initialize(accreditation)
      @acc      = accreditation
      @election = accreditation.election
    end

    def call
      Prawn::Document.new(
        page_size: [mm(BADGE_WIDTH_MM), mm(BADGE_HEIGHT_MM)],
        margin: [mm(4), mm(4), mm(4), mm(4)]
      ) do |pdf|
        render_band(pdf)
        render_header(pdf)
        render_photo(pdf)
        render_identity(pdf)
        render_meta(pdf)
        render_qr(pdf)
        render_footer(pdf)
      end.render
    end

    private

    def mm(value)
      value.mm
    end

    # Colored top band keyed to accreditation type (red=mandataire,
    # blue=national obs, indigo=intl obs, green=press, orange=intl press).
    def render_band(pdf)
      band_color = @acc.badge_color.sub("#", "")
      pdf.canvas do
        pdf.fill_color band_color
        pdf.fill_rectangle [0, pdf.bounds.top], pdf.bounds.width, mm(10)
        pdf.fill_color TEXT_DARK
      end
    end

    def render_header(pdf)
      pdf.move_down mm(4)
      pdf.fill_color "FFFFFF"
      pdf.text "BONVOTE — CEP", size: 9, style: :bold, align: :center
      pdf.fill_color TEXT_DARK
      pdf.move_down mm(3)
      pdf.text(@acc.type_label.to_s.upcase, size: 11, style: :bold, align: :center)
      pdf.move_down mm(1)
      pdf.stroke_color BORDER_LIGHT
      pdf.stroke_horizontal_rule
      pdf.stroke_color "000000"
      pdf.move_down mm(3)
    end

    # Photo slot — 35×45mm passport proportions, centered. When no photo
    # is attached we render a placeholder so the badge still prints with
    # a clean slot the issuer can manually affix a physical photo to.
    def render_photo(pdf)
      slot_w = mm(30)
      slot_h = mm(38)
      x_center = (pdf.bounds.width - slot_w) / 2.0

      if @acc.photo_url.present?
        begin
          pdf.image(
            fetch_photo_io(@acc.photo_url),
            at: [x_center, pdf.cursor],
            width: slot_w, height: slot_h, position: :center
          )
        rescue StandardError => e
          Rails.logger.warn("[AccreditationBadgePdfService] photo fetch failed: #{e.message}")
          render_photo_placeholder(pdf, x_center, slot_w, slot_h)
        end
      else
        render_photo_placeholder(pdf, x_center, slot_w, slot_h)
      end

      pdf.move_down slot_h + mm(3)
    end

    def render_photo_placeholder(pdf, x, w, h)
      pdf.stroke_color BORDER_LIGHT
      pdf.fill_color BG_LIGHT
      pdf.fill_and_stroke_rectangle [x, pdf.cursor], w, h
      pdf.fill_color TEXT_MUTED
      pdf.bounding_box([x, pdf.cursor - (h / 2.0) + mm(2)], width: w, height: mm(4)) do
        pdf.text "FOTO", size: 8, align: :center, style: :bold
      end
      pdf.fill_color TEXT_DARK
      pdf.stroke_color "000000"
    end

    def render_identity(pdf)
      pdf.fill_color TEXT_DARK
      pdf.text @acc.full_name.to_s, size: 12, style: :bold, align: :center
      pdf.move_down mm(1)
      pdf.fill_color TEXT_MUTED
      pdf.text @acc.organization.to_s, size: 8, align: :center
      pdf.fill_color TEXT_DARK
      pdf.move_down mm(2)
    end

    def render_meta(pdf)
      rows = []
      rows << ["Kòd",          @acc.accreditation_code.to_s]
      rows << ["CIN",          mask(@acc.cin_number)]           if @acc.cin_number.present?
      rows << ["BonID",        mask_bonid(@acc.bonid)]          if @acc.bonid.present?
      rows << ["Depatman",     @acc.department_code.to_s]       if @acc.department_code.present?
      rows << ["Biwo Vòt",     @acc.assigned_station_code.to_s] if @acc.assigned_station_code.present?
      rows << ["Valid pou",    election_label]
      rows << ["Emèt",         @acc.issued_at&.strftime("%d/%m/%Y") || "—"]

      pdf.table(rows,
                cell_style: { size: 7, borders: [:bottom], border_color: BORDER_LIGHT,
                              padding: [mm(1), mm(1)] },
                width: pdf.bounds.width) do |t|
        t.column(0).style(text_color: TEXT_MUTED, font_style: :bold)
        t.column(1).style(text_color: TEXT_DARK)
      end
      pdf.move_down mm(2)
    end

    # QR encodes the accreditation code — a poll worker scans it, hits
    # CEP's verification API, and sees activation status + photo match.
    def render_qr(pdf)
      qr = RQRCode::QRCode.new(qr_payload, level: :m)
      png = qr.as_png(size: 180, border_modules: 1).to_s
      qr_size = mm(22)
      x_center = (pdf.bounds.width - qr_size) / 2.0
      pdf.image StringIO.new(png), at: [x_center, pdf.cursor], width: qr_size, height: qr_size
      pdf.move_down qr_size + mm(1)
    end

    def render_footer(pdf)
      pdf.fill_color TEXT_MUTED
      pdf.text "Badj pèsonèl — pa transmisib.",      size: 6, align: :center
      pdf.text "Verifye nan bonid.ht/akreditasyon",  size: 6, align: :center
      pdf.fill_color TEXT_DARK
    end

    def qr_payload
      # Compact, versioned payload — scanner does a server round-trip to
      # resolve status, photo, revocation.
      {
        v:    1,
        typ:  "acc",
        code: @acc.accreditation_code,
        e:    @election&.id,
        bon:  @acc.bonid.to_s[0, 12]
      }.compact.to_json
    end

    def election_label
      return "—" unless @election

      [@election.title, @election.election_date&.strftime("%Y")].compact.join(" ")
    end

    def mask(value)
      return "—" if value.blank?

      s = value.to_s
      return s if s.length <= 4

      "#{s[0, 2]}••••#{s[-2, 2]}"
    end

    def mask_bonid(value)
      return "—" if value.blank?

      parts = value.to_s.split("-")
      return value.to_s if parts.length < 3

      "#{parts[0]}-••••-#{parts.last}"
    end

    def fetch_photo_io(url)
      # Supports both http(s) URLs and local paths. Callers are responsible
      # for ensuring photo_url is one of these; no follow-redirect handling
      # beyond what URI.open provides.
      if url.to_s.start_with?("http")
        require "open-uri"
        URI.parse(url).open(read_timeout: 5)
      else
        File.open(url, "rb")
      end
    end
  end
end
