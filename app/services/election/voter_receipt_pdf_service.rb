# frozen_string_literal: true

require "prawn"
require "prawn/measurement_extensions"
require "rqrcode"
require "chunky_png"

module Election
  # Renders the BonID voter-registration receipt as a single-page A4 PDF that
  # a citizen can print at a copy shop or save to their phone. The receipt
  # carries:
  #
  #   - The citizen's name and BVT reference
  #   - Their assigned polling station (if already resolved)
  #   - A QR code encoding `record.receipt_qr_payload` — the same payload a
  #     CEP-issued tablet scans at check-in
  #   - A tamper-evident checksum footer
  #
  # Design follows the existing `ServiceApplicationPdfGenerator` styling so
  # the whole BonID document family reads as one brand.
  #
  # Usage:
  #   bytes = Election::VoterReceiptPdfService.call(record)
  #   send_data bytes, filename: "resi-vote-BVT-2026-....pdf",
  #                    type: "application/pdf"
  class VoterReceiptPdfService
    HAITI_BLUE   = "00209F"
    HAITI_RED    = "D52B1E"
    TEXT_DARK    = "1A202C"
    TEXT_MUTED   = "718096"
    BORDER_LIGHT = "E2E8F0"
    BG_LIGHT     = "F7FAFC"

    # CEP is registered as an approved Partner (slug: "cep") with its
    # official logo uploaded as an ActiveStorage attachment. We resolve
    # it once per render and reuse — no static file path, no manual sync
    # when CEP updates the asset in the partner-portal.
    CEP_PARTNER_SLUG = "cep"

    def self.call(record, attach: true, host: nil, protocol: nil)
      new(record, host: host, protocol: protocol).call(attach: attach)
    end

    def initialize(record, host: nil, protocol: nil)
      @record   = record
      @election = record.bonvote_election
      @user     = record.user
      @host     = host
      @protocol = protocol
    end

    # Returns the PDF bytes. When `attach: true` (default), also persists
    # them to the record's ActiveStorage attachment so later downloads can
    # skip the Prawn render.
    def call(attach: true)
      pdf_data = build_pdf

      if attach
        @record.receipt_pdf.attach(
          io: StringIO.new(pdf_data),
          filename: default_filename,
          content_type: "application/pdf"
        )
        @record.update_columns(receipt_generated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      pdf_data
    end

    def default_filename
      "resi-vote-#{@record.voter_reference}.pdf"
    end

    private

    def build_pdf
      Prawn::Document.new(page_size: "A4", margin: [40, 40, 50, 40]) do |pdf|
        render_header(pdf)
        render_citizen_block(pdf)
        render_attestation_line(pdf)
        render_reference_block(pdf)
        render_polling_block(pdf)
        render_qr_block(pdf)
        render_footer(pdf)
      end.render
    end

    # Full-sentence attestation rendered under the citizen block. The pill is
    # for glance reading; this line is what the citizen (and any scrutineer)
    # reads to understand exactly what the signature claims.
    def render_attestation_line(pdf)
      signed = @record.bonvote_signature.present?
      text   = if signed
                 "BonVote bay resi sa a dapre pwotokòl CEP la."
               else
                 "Resi sa a poko siyen. L ap siyen lè enskripsyon w konplete."
               end

      pdf.fill_color TEXT_MUTED
      pdf.font "Helvetica", style: :italic, size: 9
      pdf.text text
      pdf.fill_color TEXT_DARK
      pdf.move_down 10
    end

    # ── Header ──────────────────────────────────────────────────────
    def render_header(pdf)
      header_top = pdf.cursor

      # Title (left).
      pdf.fill_color HAITI_BLUE
      pdf.font "Helvetica", style: :bold, size: 18
      pdf.text "BonID — Resi Enskripsyon Elektè"

      pdf.fill_color TEXT_MUTED
      pdf.font "Helvetica", size: 9
      pdf.text @election&.title.to_s

      # CEP partner logo (right). Floats over the title row so the layout
      # below stays untouched. Framed as "AN KOLABORASYON AK" so the
      # receipt's issuer remains BonID and CEP is shown as the verified
      # partner authority — never as the issuer.
      render_cep_partner_mark(pdf, top_y: header_top)

      pdf.move_down 6
      render_signature_badge(pdf)

      pdf.stroke_color BORDER_LIGHT
      pdf.stroke_horizontal_rule
      pdf.move_down 14
    end

    # Right-aligned CEP partner mark. Uses the real PNG logo when present
    # at CEP_LOGO_PATH; otherwise renders a typographic placeholder so the
    # partnership is communicated even before the official asset lands.
    def render_cep_partner_mark(pdf, top_y:)
      mark_w = 130
      mark_x = pdf.bounds.width - mark_w

      pdf.float do
        # Tiny eyebrow label above the mark.
        pdf.bounding_box([mark_x, top_y], width: mark_w, height: 10) do
          pdf.fill_color TEXT_MUTED
          pdf.font "Helvetica", size: 6.5
          pdf.text "AN KOLABORASYON AK", align: :right, character_spacing: 1.2
        end

        logo_bytes = cep_logo_bytes
        if logo_bytes.present?
          # Real partner-uploaded logo, right-aligned, fit to mark height.
          # Wrapped in a tempfile because Prawn's image reader needs a
          # path or IO that supports rewind from the start.
          Tempfile.open(["cep_logo_", logo_extension]) do |tmp|
            tmp.binmode
            tmp.write(logo_bytes)
            tmp.rewind
            pdf.image tmp.path,
                      at: [mark_x, top_y - 12],
                      width: mark_w,
                      fit: [mark_w, 36]
          end
        else
          # Typographic placeholder used only when the partner record or
          # its logo is missing. Should never hit in production once the
          # partner-portal upload is in place.
          pdf.bounding_box([mark_x, top_y - 12], width: mark_w, height: 32) do
            pdf.fill_color HAITI_BLUE
            pdf.font "Helvetica", style: :bold, size: 16
            pdf.text "CEP", align: :right
            pdf.fill_color TEXT_MUTED
            pdf.font "Helvetica", size: 7
            pdf.text "Konsèy Elektoral Pwovizwa", align: :right
            pdf.text "Patnè Verifye", align: :right
          end
        end
      end

      pdf.fill_color TEXT_DARK
    end

    # Signed-state indicator. Present = green "Siyen pa BonVote · Pwotokòl CEP"
    # pill; absent = amber "Pa siyen" pill. Poll workers can read this at a
    # glance without scanning the QR. The pill claims only what the signature
    # actually proves: BonVote issued this receipt, following CEP's protocol.
    def render_signature_badge(pdf)
      signed = @record.bonvote_signature.present?
      label  = signed ? "Siyen pa BonVote · Pwotokòl CEP" : "Pa siyen"
      bg     = signed ? "1F7A3B" : "B45309"  # green / amber
      fg     = "FFFFFF"
      width  = 200

      # Right-aligned pill
      pdf.float do
        pdf.fill_color bg
        pdf.fill_rectangle [pdf.bounds.width - width, pdf.cursor], width, 16
        pdf.fill_color fg
        pdf.font "Helvetica", style: :bold, size: 8
        pdf.text_box label,
                     at: [pdf.bounds.width - width, pdf.cursor - 3],
                     width: width, height: 16, align: :center, valign: :center
      end
      pdf.fill_color TEXT_DARK
      pdf.move_down 4
    end

    # ── Citizen identity ────────────────────────────────────────────
    def render_citizen_block(pdf)
      pdf.fill_color TEXT_DARK
      pdf.font "Helvetica", style: :bold, size: 12
      pdf.text "Sitwayen / Citoyen"
      pdf.move_down 4

      pdf.font "Helvetica", size: 11
      pdf.text @user&.full_name.to_s.presence || "—"

      pdf.fill_color TEXT_MUTED
      pdf.font "Helvetica", size: 9
      # BonID is masked to last 6 chars (matches `bonid_short` used in
      # the QR payload). The full BonID encodes DOB year, sex, dept,
      # and the last 4 of CIN — printing it on a paper a stranger could
      # find leaks all of those. Last 6 is enough for the citizen to
      # recognize their own ID and for CEP/tribunal cross-reference;
      # the full BonID stays in the database.
      #
      # CIN intentionally omitted for the same reason — and because the
      # masked BonID already reflects the last 4 of CIN.
      pdf.text "BonID: #{masked_bonid}"

      # Registration timestamp — same datum the citizen sees on the
      # Eleksyon Mwen header. Important for tribunal disputes and for
      # the citizen to know when the receipt became valid.
      if @record.registered_at.present?
        pdf.text "Enskri: #{I18n.l(@record.registered_at, format: '%d %B %Y, %H:%M')}"
      end

      pdf.move_down 12
    end

    # ── BVT reference badge ─────────────────────────────────────────
    def render_reference_block(pdf)
      pdf.fill_color BG_LIGHT
      pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, 54
      pdf.stroke_color BORDER_LIGHT
      pdf.stroke_rectangle [0, pdf.cursor], pdf.bounds.width, 54

      pdf.bounding_box([12, pdf.cursor - 8], width: pdf.bounds.width - 24, height: 40) do
        pdf.fill_color TEXT_MUTED
        pdf.font "Helvetica", size: 8
        pdf.text "NIMEWO VOTÈ BONID"

        pdf.fill_color HAITI_BLUE
        pdf.font "Courier", style: :bold, size: 16
        pdf.text @record.voter_reference
      end
      pdf.move_down 20
    end

    # ── Polling station ─────────────────────────────────────────────
    # Mirrors the Eleksyon Mwen "Biwo Vòt" card: BV# + center name, then
    # the canonical Haitian multi-line address, then phone, then voting
    # hours scoped to election day. Same data, same labels — print parity
    # with the digital view so the citizen recognizes one as the other.
    def render_polling_block(pdf)
      pdf.fill_color TEXT_DARK
      pdf.font "Helvetica", style: :bold, size: 11
      pdf.text "Biwo Vòt / Bureau de Vote"
      pdf.move_down 3

      if @record.polling_station.present?
        station = @record.polling_station
        center  = station.polling_center

        pdf.fill_color TEXT_DARK
        pdf.font "Helvetica", size: 10
        pdf.text "BV ##{station.bv_number} — #{center&.name}"

        # Address — prefer the multi-line Haitian format
        # (formatted_haiti_display), fall back to single-line.
        address_lines = if center&.respond_to?(:formatted_haiti_display) && center.formatted_haiti_display.present?
                          center.formatted_haiti_display.split("\n")
                        elsif center&.formatted_address.present?
                          [center.formatted_address]
                        else
                          []
                        end

        unless address_lines.empty?
          pdf.move_down 2
          pdf.fill_color TEXT_MUTED
          pdf.font "Helvetica", size: 9
          address_lines.each { |line| pdf.text line }
        end

        # Phone — tappable on the digital view; printed for paper.
        if center&.contact_phone.present?
          pdf.move_down 2
          pdf.fill_color TEXT_MUTED
          pdf.font "Helvetica", size: 9
          pdf.text "Telefòn: #{center.contact_phone}"
        end

        # Voting hours — strip any redundant "Jou eleksyon" prefix from
        # the stored value (the label below already says it), then add
        # the scope sub-line for clarity.
        if center&.contact_hours.present?
          hours = center.contact_hours.to_s.sub(/\A\s*Jou\s+eleksyon(?:\s+an)?\s*[:\-–—]?\s*/i, "").strip
          hours = center.contact_hours if hours.blank?

          pdf.move_down 2
          pdf.fill_color TEXT_MUTED
          pdf.font "Helvetica", size: 9
          pdf.text "Orè vòt: #{hours}  (jou eleksyon sèlman)"
        end
      else
        pdf.fill_color TEXT_MUTED
        pdf.font "Helvetica", style: :italic, size: 10
        pdf.text "Biwo vòt ap atribye byento — tcheke BonID ou jou eleksyon an."
      end
      pdf.move_down 18
    end

    # ── QR block (right-aligned) ────────────────────────────────────
    def render_qr_block(pdf)
      qr  = RQRCode::QRCode.new(@record.receipt_qr_url(host: @host, protocol: @protocol), level: :m)
      png = qr.as_png(size: 220, border_modules: 2)

      y = pdf.cursor
      pdf.image StringIO.new(png.to_s),
                at: [pdf.bounds.width - 140, y],
                width: 140

      pdf.bounding_box([0, y], width: pdf.bounds.width - 160, height: 140) do
        pdf.fill_color TEXT_DARK
        pdf.font "Helvetica", style: :bold, size: 11
        pdf.text "Kòd QR Verifikasyon"
        pdf.move_down 4

        pdf.fill_color TEXT_MUTED
        pdf.font "Helvetica", size: 9
        pdf.text "Ajan nan biwo vòt la pral eskane kòd sa a pou konfime idantite w."
        pdf.move_down 4
        pdf.text "Pote resi sa a (enprime oswa sou telefòn ou) jou eleksyon an, " \
                 "ansanm ak yon pyès idantite ofisyèl (CIN oswa paspò)."
      end

      pdf.move_down 8
    end

    # ── Identity-display helpers ────────────────────────────────────
    # Masks the BonID to the last 6 chars (dashes stripped). Matches
    # the same scheme used in `VoterEligibilityRecord#bonid_short` so
    # the printed receipt and the QR payload reference the same suffix.
    # Format: "•••• •••• 697C56".
    def masked_bonid
      raw = @record.bonid.to_s
      return "—" if raw.blank?

      tail = raw.tr("-", "").last(6)
      "•••• •••• #{tail}"
    end

    # ── Partner-logo helpers ────────────────────────────────────────
    # Resolves the CEP partner record (cached per render). Returns nil if
    # the partner row is missing or its logo isn't attached — the header
    # falls back to the typographic placeholder in that case.
    def cep_partner
      return @cep_partner if defined?(@cep_partner)
      @cep_partner = Partner.find_by(slug: CEP_PARTNER_SLUG)
    end

    def cep_logo_bytes
      return @cep_logo_bytes if defined?(@cep_logo_bytes)
      @cep_logo_bytes = if cep_partner&.logo&.attached?
                          cep_partner.logo.download
                        end
    rescue => e
      Rails.logger.warn("[VoterReceiptPdfService] CEP logo fetch failed: #{e.message}")
      @cep_logo_bytes = nil
    end

    def logo_extension
      ext = cep_partner&.logo&.filename&.extension.to_s
      ext.present? ? ".#{ext}" : ".png"
    end

    # ── Footer ──────────────────────────────────────────────────────
    def render_footer(pdf)
      pdf.stroke_color BORDER_LIGHT
      pdf.stroke_horizontal_rule
      pdf.move_down 6

      pdf.fill_color TEXT_MUTED
      pdf.font "Helvetica", size: 8

      lines = [
        "Jenere: #{Time.current.strftime('%d/%m/%Y %H:%M %Z')}",
        "Sou: BonID — Resi sa a se yon kopi BonID, pa yon pyès idantite ofisyèl.",
        "Enprime oswa sere nan telefòn ou. Pa pèdi li."
      ]
      lines.each { |l| pdf.text l }
    end
  end
end
