# frozen_string_literal: true

module Citizens
  class RegistrationsController < Devise::RegistrationsController
    layout "citizen_auth"

    before_action :load_partner

    def new
      if @partner.nil?
        redirect_to partners_path, alert: "Citizen sign-up must be started via a verified partner."
      else
        super
      end
    end

    def create
      if @partner.nil?
        redirect_to partners_path, alert: "Invalid or unverified partner."
        return
      end

      # Detect existing verified user → route to sign-in instead of duplicate registration
      existing_email = params.dig(:citizen, :email)&.strip&.downcase
      if existing_email.present?
        existing_user = User.find_by("LOWER(email) = ?", existing_email)
        if existing_user
          store_partner_context_for_otp(@partner)

          if existing_user.identity_submissions.status_approved.exists?
            redirect_to citizens_otp_sign_in_path(from_partner: @partner.slug),
                        notice: "You have already verified. Sign in to continue to #{@partner.name}."
          else
            redirect_to citizens_otp_sign_in_path(from_partner: @partner.slug),
                        notice: "You already have an account. Sign in to continue."
          end
          return
        end
      end

      # OTP-only: inject a random password so Devise validations pass
      random_pw = SecureRandom.hex(32)
      params[:citizen][:password] = random_pw
      params[:citizen][:password_confirmation] = random_pw

      super do |citizen|
        if citizen.persisted?
          # Assign citizen role
          citizen.add_role(:citizen) if citizen.respond_to?(:add_role)

          # Link to initiating partner
          citizen.update(partner: @partner)

          # Generate OTP for immediate 2FA verification
          CitizenOtpService.new(citizen).generate!(ip: request.remote_ip)

          # Store pending consent context securely
          cookies.encrypted[:pending_consent] = {
            value: {
              partner_id: @partner.id,
              scopes: [ "identity" ],
              redirect_uri: citizens_dashboard_path
            }.to_json,
            expires: 15.minutes.from_now,
            httponly: true,
            secure: Rails.application.config.force_ssl,
            same_site: :strict
          }

          # Optional: Log successful registration
          Rails.logger.info("New citizen registered: #{citizen.email} via partner #{@partner.slug}")
        end
      end
    end

    protected

    # Redirect to OTP verification after successful signup
    def after_sign_up_path_for(resource)
      new_citizen_otp_session_path(
        email: resource.email,
        signup: "true",
        partner_slug: @partner&.slug
      )
    end

    private

    def load_partner
      slug = params[:partner].presence || params.dig(:citizen, :partner)
      @partner = Partner.find_by(slug: slug)
      @partner = nil unless @partner&.verified_at?
    end

    def sign_up_params
      params.require(:citizen).permit(:email, :phone)
    end

    # Preserve partner OAuth context so the OTP sign-in flow can
    # continue the OAuth handoff after authentication
    def store_partner_context_for_otp(partner)
      pending_data = {
        partner_id: partner.id,
        partner_slug: partner.slug,
        scopes: %w[openid profile email],
        redirect_uri: partner.primary_redirect_uri.presence || root_url,
        state: SecureRandom.urlsafe_base64(32),
        created_at: Time.current.to_i
      }

      session[:pending_consent] = pending_data
      session[:pending_partner_slug] = partner.slug

      cookies.encrypted[:pending_consent] = {
        value: pending_data.to_json,
        expires: 30.minutes.from_now,
        httponly: true,
        secure: Rails.application.config.force_ssl
      }
    end
  end
end
