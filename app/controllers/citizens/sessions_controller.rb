# frozen_string_literal: true

module Citizens
  class SessionsController < Devise::SessionsController
    layout "citizen_auth"

    respond_to :html, :turbo_stream

    protect_from_forgery with: :exception, prepend: true

    # Skip CSRF for Turbo Stream OTP actions (safe because OTP is one-time + rate-limited)
    skip_before_action :verify_authenticity_token,
                       only: %i[create_otp verify_otp resend_otp],
                       if: -> { request.format.turbo_stream? }

    before_action :rate_limit_otp_requests, only: %i[create_otp verify_otp]

    # =========================================================
    # Standard Login → Redirect to OTP (password login removed)
    # =========================================================
    def new
      redirect_to citizens_otp_sign_in_path(from_partner: params[:from_partner])
    end

    def create
      redirect_to citizens_otp_sign_in_path(from_partner: params[:from_partner]),
                  notice: "Please use one-time code to sign in."
    end

    # =========================================================
    # OTP (Passwordless) Login Flow
    # =========================================================
    def otp_sign_in
      partner_slug = params[:from_partner] || params[:partner_slug]
      session[:login_source] = partner_slug.present? ? "partner:#{partner_slug}" : "citizen_portal"
      session[:pending_partner_slug] = partner_slug if partner_slug.present?
      @partner = Partner.find_by(slug: partner_slug) if partner_slug.present?

      render :new_otp, locals: { partner_slug: partner_slug }
    end

    def create_otp
      raw_input    = params.dig(:citizen, :email)&.strip&.downcase
      partner_slug = params[:from_partner] || params[:partner_slug] || session[:pending_partner_slug]

      PartnerSessionService.new(session, params).store! rescue nil

      if raw_input.blank?
        return redirect_to citizens_otp_sign_in_path(partner_slug: partner_slug),
                           alert: "Please enter your email or BonID number."
      end

      user =
        if raw_input.include?("@")
          User.find_by("LOWER(email) = ?", raw_input)
        else
          User.find_by(id_number: raw_input.upcase)
        end

      unless user
        return redirect_to citizens_otp_sign_in_path(partner_slug: partner_slug),
                           alert: "No account found with that email or BonID."
      end

      # Ensure citizen role
      user.add_role(:citizen) unless user.has_role?(:citizen)

      # Generate and send OTP
      CitizenOtpService.new(user).generate!(fingerprint: request_fingerprint)

      # Store pending login context
      session[:pending_citizen_id] = user.id
      session[:login_source] = "partner:#{partner_slug}" if partner_slug.present?
      session[:pending_partner_slug] = partner_slug if partner_slug.present?

      redirect_to citizens_verify_otp_path(
        partner_slug: partner_slug,
        email: user.email,
        signup: "false"
      ), notice: "We sent a one-time code to your email."
    rescue => e
      Rails.logger.error("OTP generation failed: #{e.message}")
      redirect_to citizens_otp_sign_in_path(partner_slug: partner_slug),
                  alert: "Could not send code. Please try again."
    end

    def verify_otp
      user = User.find_by(id: session[:pending_citizen_id])
      partner_slug = params[:partner_slug] || params[:from_partner] || session[:pending_partner_slug]
      @partner = Partner.find_by(slug: partner_slug) if partner_slug.present?

      unless user
        return redirect_to citizens_otp_sign_in_path,
                           alert: "Session expired. Please start again."
      end

      if request.post? && params[:otp].present?
        if CitizenOtpService.new(user).verify!(params[:otp], fingerprint: request_fingerprint)
          sign_in_citizen(user, params[:otp], partner_slug)
        else
          flash.now[:alert] = "Invalid or expired code."
          render :verify_otp, status: :unprocessable_entity
        end
      else
        render :verify_otp, locals: { partner_slug: partner_slug, signup: params[:signup], email: user.email }
      end
    end

    def resend_otp
      user = User.find_by(id: session[:pending_citizen_id])
      partner_slug = params[:partner_slug] || params[:from_partner] || session[:pending_partner_slug]

      unless user
        return redirect_to citizens_otp_sign_in_path,
                           alert: "Session expired. Please start again."
      end

      CitizenOtpService.new(user).generate!(fingerprint: request_fingerprint)
      flash.now[:notice] = "New code sent to your email."

      render :verify_otp, locals: { partner_slug: partner_slug, signup: params[:signup], email: user.email }
    rescue => e
      Rails.logger.error("OTP resend failed: #{e.message}")
      flash.now[:alert] = "Could not resend code. Try again."
      render :verify_otp, locals: { partner_slug: partner_slug, signup: params[:signup], email: user.email }
    end

    # =========================================================
    # Sign Out
    # =========================================================
    def destroy
      signed_out = sign_out(:citizen)
      set_flash_message!(:notice, :signed_out) if signed_out

      respond_to do |format|
        format.html { redirect_to citizens_otp_sign_in_path }
        format.turbo_stream { redirect_to citizens_otp_sign_in_path, status: :see_other }
      end
    end

    # =========================================================
    # Protected
    # =========================================================
    protected

    def after_sign_in_path_for(_resource)
      # ✅ Only go to consent if handoff is REAL + FRESH
      if oauth_handoff_fresh?
        return consent_oauth_index_path(partner_slug: session[:pending_partner_slug])
      end

      # stale oauth handoff should not hijack the session
      clear_oauth_handoff!

      citizens_dashboard_path
    end

    def after_sign_out_path_for(_resource_or_scope)
      citizens_otp_sign_in_path
    end

    # =========================================================
    # Private
    # =========================================================
    private

    def sign_in_citizen(user, otp_code = nil, partner_slug = nil)
      login_source = partner_slug.present? ? "partner:#{partner_slug}" : "citizen_portal"

      sign_in(:citizen, user)

      citizen_profile = user.citizen_profile || user.create_citizen_profile!

      # Preserve partner consent context (OAuth handoff)
      if partner_slug.present?
        partner = Partner.find_by(slug: partner_slug)

        if partner
          existing = session[:pending_consent]
          existing = JSON.parse(existing) rescue existing if existing.is_a?(String)
          existing = {} unless existing.is_a?(Hash)

          existing_redirect = existing[:redirect_uri].presence || existing["redirect_uri"].presence
          existing_state    = existing[:state].presence || existing["state"].presence
          existing_scopes   = existing[:scopes].presence || existing["scopes"].presence

          # ✅ ALWAYS ensure state exists (required for CSRF/state validation)
          state = existing_state.presence || SecureRandom.urlsafe_base64(32)

          pending_data = {
            partner_id: partner.id,
            partner_slug: partner.slug,
            scopes: (existing_scopes || %w[openid profile email]),
            redirect_uri: existing_redirect.presence || partner.primary_redirect_uri.presence || root_url,
            state: state,
            created_at: Time.current.to_i
          }

          session[:pending_consent] = pending_data
          session[:pending_partner_slug] = partner_slug

          cookies.encrypted[:pending_consent] = {
            value: pending_data.to_json,
            expires: 30.minutes.from_now,
            httponly: true,
            secure: Rails.application.config.force_ssl
          }
        end
      end

      # Audit login
      CitizenSession.create!(
        user: user,
        citizen_profile: citizen_profile,
        otp_digest: otp_code.present? ? BCrypt::Password.create(otp_code) : nil,
        login_source: login_source,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        device_fingerprint: request_fingerprint,
        used_at: Time.current,
        expires_at: 30.minutes.from_now
      )

      session[:login_source] = login_source
      session.delete(:pending_citizen_id)

      redirect_to after_sign_in_path_for(user),
                  notice: params[:signup] == "true" ? "Welcome! Please complete your profile." : "Welcome back!"
    rescue => e
      Rails.logger.error("Citizen sign-in failed: #{e.message}")
      redirect_to citizens_otp_sign_in_path,
                  alert: "Login failed. Please try again."
    end

    # -----------------------------
    # OAuth Handoff Safety
    # -----------------------------

    def oauth_handoff_data
      data = session[:pending_consent]
      data = JSON.parse(data) rescue data if data.is_a?(String)
      return nil unless data.is_a?(Hash)

      data.with_indifferent_access
    end

    def oauth_handoff_fresh?
      data = oauth_handoff_data
      return false if data.blank?
      return false if data[:partner_id].blank?
      return false if data[:created_at].blank?

      Time.at(data[:created_at].to_i) >= 30.minutes.ago
    rescue
      false
    end

    def clear_oauth_handoff!
      session.delete(:pending_consent)
      session.delete(:pending_partner_slug)
      cookies.encrypted[:pending_consent] = nil
    end

    # -----------------------------
    # Misc
    # -----------------------------

    def request_fingerprint
      "#{request.remote_ip}-#{request.user_agent}"
    end

    def rate_limit_otp_requests
      return if Rails.env.development? || Rails.env.test?

      key = "otp_attempts:#{request_fingerprint}"
      count = Rails.cache.fetch(key, expires_in: 15.minutes) { 0 }

      if count >= 10
        render plain: "Too many attempts. Please try again later.", status: :too_many_requests
        return
      end

      Rails.cache.write(key, count + 1, expires_in: 15.minutes)
    end
  end
end


# # app/controllers/citizens/sessions_controller.rb
# module Citizens
#   class SessionsController < ApplicationController
#     layout "citizen_auth"

#     def new
#     end

#     def create
#       raw_input = params.dig(:citizen, :email)&.strip
#       return redirect_to(citizens_sign_in_path, alert: "Please enter your email or BonID number.") if raw_input.blank?

#       user =
#         if raw_input.include?("@")
#           User.find_by("LOWER(email) = ?", raw_input.downcase)
#         else
#           User.find_by(id_number: raw_input.upcase) # normalize BonID like HT1234
#         end

#       if user.nil?
#         # Case 1: User truly doesn’t exist
#         redirect_to citizens_sign_in_path,
#                     alert: "No account found for this email or BonID number."

#       elsif !user.citizen?
#         # Case 2: User exists but is not a citizen
#         redirect_to citizens_sign_in_path,
#                     alert: "⚠️ This account exists but is not registered as a citizen account."

#       elsif user.has_verified_bonid?
#         # Case 3: Citizen exists + verified BonID → OTP flow
#         CitizenOtpService.new(user).generate!(fingerprint: request_fingerprint)
#         session[:pending_citizen_id] = user.id

#         respond_to do |format|
#           format.turbo_stream do
#             render partial: "shared/turbo_redirect",
#                    formats: [ :turbo_stream ],
#                    locals: { redirect_path: citizens_verify_otp_path }
#           end
#           format.html do
#             redirect_to citizens_verify_otp_path,
#                         notice: "We sent a code to your email."
#           end
#         end

#       else
#         # Case 4: Citizen exists but BonID is not verified (new, rejected, or pending)
#         redirect_to partners_path,
#                     alert: "⚠️ Your BonID is not verified. Please visit a verified partner (e.g. bank, police, embassy) to complete verification."
#       end
#     end



#       def resend_otp
#         user = User.find_by(id: session[:pending_citizen_id])

#         unless user&.citizen?
#           redirect_to citizens_sign_in_path, alert: "Session expired. Please sign in again."
#           return
#         end

#         CitizenOtpService.new(user).generate!(fingerprint: request_fingerprint)

#         respond_to do |format|
#           format.turbo_stream do
#             flash.now[:notice] = "We sent you a new code."
#             render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
#           end
#           format.html do
#             redirect_to citizens_verify_otp_path, notice: "We sent you a new code."
#           end
#         end
#       end

#     def verify_otp
#       user = User.find_by(id: session[:pending_citizen_id])
#       unless user
#         redirect_to citizens_sign_in_path, alert: "Session expired. Please sign in again."
#         return
#       end

#       if request.post? && params[:otp].present?
#         if CitizenOtpService.new(user).verify!(params[:otp].to_s, fingerprint: request_fingerprint)
#           sign_in_citizen(user)
#         else
#           flash.now[:alert] = "Invalid or expired code."
#           render :verify_otp, status: :unprocessable_entity
#         end
#       else
#         render :verify_otp
#       end
#     end

#     def destroy
#       sign_out(current_user) if current_user
#       reset_session
#       redirect_to root_path, notice: "Signed out successfully."
#     end

#     private

#     def sign_in_citizen(user)
#       sign_in(user) # Devise
#       session.delete(:pending_citizen_id)
#       session.delete(:pending_citizen_email)

#       # ✅ Handle BonID status AFTER login
#       if user.has_verified_bonid?
#         redirect_to user_dashboard_path, notice: "Welcome back, #{user.full_name}!"
#       elsif user.identity_submissions.rejected.exists?
#         redirect_to user_dashboard_path, alert: "Your BonID was rejected. Please resubmit."
#       else
#         redirect_to user_dashboard_path, alert: "You have not submitted or verified your BonID yet."
#       end
#     end

#     def request_fingerprint
#       "#{request.remote_ip}-#{request.user_agent}"
#     end
#   end
# end
