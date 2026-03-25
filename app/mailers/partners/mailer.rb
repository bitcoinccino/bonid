# app/mailers/partners/mailer.rb
require "rqrcode"
require "chunky_png"
require "base64"

module Partners
  class Mailer < VerifyemMailer
    include Rails.application.routes.url_helpers

    default template_path: "partners/mailer"

    # Allow URL helpers inside emails
    def default_url_options
      Rails.application.config.action_mailer.default_url_options
    end

    # =====================================================================
    # 1. APPLICATION RECEIVED EMAIL
    # =====================================================================
    def confirmation_email
      @partner = params[:partner]
      @verification_url = partners_verify_url(token: @partner.email_verification_token)

      mail(
        to: @partner.email,
        subject: "Welcome to BonID – Partner Application Received"
      )
    end

    # =====================================================================
    # 2. VERIFICATION EMAIL (Partner clicks link → verifies email)
    # =====================================================================
    def verification_email
      @partner = params[:partner]

      # Don't send if email already verified
      return if @partner.email_verified?

      @verification_url = partners_verify_url(token: @partner.email_verification_token)
      @qr_png_base64 = generate_qr_with_logo(@verification_url, @partner)

      mail(
        to: @partner.email,
        subject: "BonID – Verify Your Partner Application"
      )
    end

    # =====================================================================
    # 3. APPROVED EMAIL (Admin approves Partner application)
    # =====================================================================
    def approved_email
      @partner = params[:partner]

      @verification_url = partners_verify_url(token: @partner.email_verification_token)
      @qr_png_base64 = generate_qr_with_logo(@verification_url, @partner)

      mail(
        to: @partner.email,
        subject: "BonID – Your Partner Account is Approved"
      )
    end

    # =====================================================================
    # 4. REJECTION EMAIL (Admin rejects application)
    # =====================================================================
    def reject_email
      @partner = params[:partner]
      @reason  = params[:reason]
      @comment = params[:comment]

      mail(
        to: @partner.email,
        subject: "BonID – Your Partner Application Has Been Rejected"
      )
    end

    # =====================================================================
    # QR Generator (with Logo Overlay)
    # =====================================================================
    private

    def generate_qr_with_logo(url, partner)
      qrcode = RQRCode::QRCode.new(url)

      png = qrcode.as_png(
        size: 480,
        border_modules: 4,
        color: "000",
        fill: "fff"
      )

      qr_img = ChunkyPNG::Image.from_io(StringIO.new(png.to_s))

      return Base64.strict_encode64(qr_img.to_blob) unless partner.logo.attached?

      begin
        logo_img = ChunkyPNG::Image.from_io(StringIO.new(partner.logo.download))

        max_size = (qr_img.width * 0.25).to_i
        logo_img = logo_img.resize(max_size, max_size)

        offset_x = (qr_img.width - logo_img.width) / 2
        offset_y = (qr_img.height - logo_img.height) / 2

        qr_img.compose!(logo_img, offset_x, offset_y)

      rescue => e
        Rails.logger.error "QR embed failed: #{e.class} – #{e.message}"
      end

      Base64.strict_encode64(qr_img.to_blob)
    end
  end
end
