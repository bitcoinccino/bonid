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

    def self.call(record, attach: true)
      new(record).call(attach: attach)
    end

    def initialize(record)
      @record   = record
      @election = record.bonvote_election
      @user     = record.user
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
        render_reference_block(pdf)
        render_polling_block(pdf)
        render_qr_block(pdf)
        render_footer(pdf)
      end.render
    end

    # ── Header ──────────────────────────────────────────────────────
    def render_header(pdf)
      pdf.fill_color HAITI_BLUE
      pdf.font "Helvetica", style: :bold, size: 18
      pdf.text "BonID — Resi Enskripsyon Elektè"

      pdf.fill_color TEXT_MUTED
      pdf.font "Helvetica", size: 9
      pdf.text @election&.title.to_s
      pdf.move_down 6

      pdf.stroke_color BORDER_LIGHT
      pdf.stroke_horizontal_rule
      pdf.move_down 14
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
      pdf.text "BonID: #{@record.bonid.presence || '—'}"
      pdf.text "CIN:   #{@record.cin_number.presence || '—'}"
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

        if center&.formatted_address.present?
          pdf.fill_color TEXT_MUTED
          pdf.font "Helvetica", size: 9
          pdf.text center.formatted_address
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
      payload_json = @record.receipt_qr_payload.to_json
      qr = RQRCode::QRCode.new(payload_json, level: :m)
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
