# frozen_string_literal: true

require "prawn"
require "base64"
require "openssl"

class VisitorMailer < ApplicationMailer
  default from: "bontouris@verifyem.ht"
  layout "mailer"

  # ------------------------------------------------------------
  # 1) Email verification OTP
  # ------------------------------------------------------------
  def email_verification
    @visitor = params[:visitor]
    @email_product = "bontouris"

    mail(
      to: @visitor.email,
      subject: "Verify Your Email – BonTouris ID"
    )
  end

  # ------------------------------------------------------------
  # 2) Documents received
  # ------------------------------------------------------------
  def documents_received
    @visitor = params[:visitor]
    @email_product = "bontouris"

    mail(
      to: @visitor.email,
      subject: "BonTouris ID – Documents Received"
    )
  end

  # ------------------------------------------------------------
  # 3) Welcome / Approved (no PDF attachment)
  # Optionally embeds QR as CID if visitor_qr_png_base64 is present
  # ------------------------------------------------------------
  def welcome
    @visitor = params[:visitor]
    @email_product = "bontouris"

    attach_qr_inline!(@visitor)

    mail(
      to: @visitor.email,
      subject: "Your BonTouris ID Has Been Approved 🇭🇹"
    )
  end

  # ------------------------------------------------------------
  # 4) Rejected
  # ------------------------------------------------------------
  def rejected
    @visitor = params[:visitor]
    @reason_label = @visitor.rejection_reason_label
    @notes        = @visitor.rejection_notes
    @email_product = "bontouris"

    mail(
      to: @visitor.email,
      subject: "BonTouris ID – Action Required"
    )
  end

  # ------------------------------------------------------------
  # 5) Scan Alert
  # ------------------------------------------------------------
  def scan_alert
    @event   = params[:event]
    @visitor = @event.visitor_submission
    @email_product = "bontouris"

    mail(
      to: @visitor.email,
      subject: "BonTouris ID Scan Alert — #{@visitor.bonid}"
    )
  end

  private

  # ------------------------------------------------------------
  # Inline QR attachment (CID) for welcome email
  # ------------------------------------------------------------
  def attach_qr_inline!(visitor)
    return unless visitor&.visitor_qr_png_base64.present?

    attachments.inline["visitor_qr.png"] = {
      mime_type: "image/png",
      content: Base64.decode64(visitor.visitor_qr_png_base64)
    }
  rescue StandardError => e
    Rails.logger.error("[VisitorMailer] Failed to attach QR inline: #{e.class} – #{e.message}")
  end

  # ============================================================
  # PDF GENERATION (still here if you want it later)
  # ============================================================
  def generate_pdf
    logo_path   = Rails.root.join("app/assets/images/verifyem_logo.png")
    flag_path   = Rails.root.join("app/assets/images/haiti_flag.png")
    qr_data     = @visitor.visitor_qr_png_base64
    selfie_blob = @visitor.selfie if @visitor.selfie&.attached?

    secret  = Rails.application.credentials.visitor_qr_secret || "visitor-qr-fallback"
    payload = @visitor.bonid.to_s

    checksum =
      if payload.present?
        OpenSSL::HMAC.hexdigest("SHA256", secret, payload).last(8).upcase
      else
        "UNISSUED"
      end

    Prawn::Document.new(page_size: "A4", margin: [ 50, 50, 70, 50 ]) do |pdf|
      pdf.canvas do
        pdf.fill_color "EEEEEE"
        pdf.font "Helvetica", size: 60
        pdf.rotate(30, origin: [ 0, 0 ]) { pdf.draw_text "PRIVATE — DO NOT SHARE", at: [ 100, 300 ] }
        pdf.fill_color "000000"
      end

      fonts_dir = Rails.root.join("app/assets/fonts")
      pdf.font_families.update(
        "Montserrat" => {
          normal: safe_font(fonts_dir, "Montserrat-Regular.ttf"),
          bold:   safe_font(fonts_dir, "Montserrat-Bold.ttf")
        },
        "Inter" => {
          normal: safe_font(fonts_dir, "Inter-Regular.ttf"),
          bold:   safe_font(fonts_dir, "Inter-Bold.ttf")
        }
      )

      pdf.font "Montserrat"

      pdf.image logo_path.to_s, width: 90, position: :center if File.exist?(logo_path)
      pdf.move_down 6
      pdf.image flag_path.to_s, width: 60, position: :center if File.exist?(flag_path)

      pdf.move_down 14
      pdf.text "BonTouris ID Certificate", size: 26, style: :bold, align: :center, color: "00209F"
      pdf.move_down 6
      pdf.font "Inter", size: 12
      pdf.text "Issued & Verified by Verifyem", align: :center, color: "444444"

      pdf.stroke_horizontal_rule
      pdf.move_down 30

      start_y = pdf.cursor

      if selfie_blob
        Tempfile.open([ "visitor_photo", ".jpg" ]) do |file|
          file.binmode
          file.write(selfie_blob.download)
          file.rewind

          pdf.bounding_box([ 0, start_y ], width: 150, height: 200) do
            pdf.rounded_rectangle([ 0, 200 ], 150, 200, 12)
            pdf.stroke
            pdf.image file.path, fit: [ 140, 180 ], position: :center
          end
        end
      end

      pdf.bounding_box([ 170, start_y ], width: pdf.bounds.width - 170) do
        pdf.font "Inter", size: 13
        full_name = [ @visitor.title, @visitor.first_name, @visitor.middle_name, @visitor.last_name ].compact.join(" ").squish
        pdf.text "Full Name: <b>#{full_name}</b>", inline_format: true
        pdf.text "BonTouris ID: <b>#{@visitor.bonid}</b>", inline_format: true
        pdf.text "Nationality: #{@visitor.nationality}"
        pdf.text "Purpose of Visit: #{@visitor.purpose_of_visit}"
        pdf.text "Expected Stay: #{@visitor.stay_duration_days || '—'} days"
        pdf.text "Valid Until: #{@visitor.expires_at&.strftime('%B %d, %Y')}"
      end

      pdf.move_down 30

      if qr_data.present?
        Tempfile.open([ "visitor_qr", ".png" ]) do |qr|
          qr.binmode
          qr.write(Base64.decode64(qr_data))
          qr.rewind
          pdf.image qr.path, width: 200, position: :center
        end
      end

      pdf.move_down 15
      pdf.font "Inter", size: 10, style: :italic
      pdf.fill_color "555555"
      pdf.text "Valid only when verified online at verifyem.com", align: :center
      pdf.fill_color "000000"

      pdf.move_down 25
      pdf.stroke_horizontal_rule
      pdf.move_down 10

      pdf.font "Inter", size: 10
      pdf.text "Offline Verification: <b>#{checksum}</b>", align: :center, inline_format: true
      pdf.move_down 6
      pdf.text "verifyem.ht • Secure Digital Verification", align: :center, size: 9
    end.render
  end

  def safe_font(dir, filename)
    path = dir.join(filename)
    File.exist?(path) ? path.to_s : "Helvetica"
  end
end
