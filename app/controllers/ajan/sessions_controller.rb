# frozen_string_literal: true

# Ajan::SessionsController
# =========================
# Passwordless OTP sign-in for the Agent Portal. Same User table as
# citizens/reviewers — the :agent devise scope just gives agents a
# dedicated, correctly-branded login door instead of forcing them
# through /citizens/sign_in.
#
# Auth flow (mirrors Citizens::SessionsController):
#   GET  /ajan/konekte          → redirects to /ajan/konekte-kod
#   GET  /ajan/konekte-kod      → email/BonID input form
#   POST /ajan/konekte-kod      → generate OTP, send email, go to verify
#   GET  /ajan/verifye-kod      → 6-digit code input form
#   POST /ajan/verifye-kod      → verify code, sign_in(:agent), go to tablo
#   POST /ajan/voye-kod         → resend code
#
# Gates on verify (order matters — fail cheap first):
#   1. OTP valid (CitizenOtpService.verify!)
#   2. Must hold an agent-tier rolify role
#   3. Must be bound to a partner
#   4. BonID must be verified
module Ajan
  class SessionsController < Devise::SessionsController
    layout "ajan"
    helper AjanHelper
    respond_to :html

    before_action :rate_limit_otp_requests, only: %i[create_otp verify_otp]

    # =========================================================
    # Password login is disabled — always route to OTP
    # =========================================================

    # GET /ajan/konekte
    def new
      redirect_to ajan_otp_sign_in_path
    end

    # POST /ajan/konekte
    def create
      redirect_to ajan_otp_sign_in_path,
                  notice: "Tanpri itilize kòd yon fwa a pou w konekte."
    end

    # =========================================================
    # OTP (Passwordless) Login Flow
    # =========================================================

    # GET /ajan/konekte-kod
    def otp_sign_in
      render :new_otp
    end

    # POST /ajan/konekte-kod
    def create_otp
      email = params.dig(:agent, :email)&.strip&.downcase

      if email.blank? || !email.include?("@")
        return redirect_to ajan_otp_sign_in_path,
                           alert: "Tanpri antre yon email valid."
      end

      user = User.find_by("LOWER(email) = ?", email)

      # Fail cheap: reject non-agents BEFORE sending a code. No leaking
      # whether the account exists — same generic message either way.
      unless user && agent_account?(user)
        return redirect_to ajan_otp_sign_in_path,
                           alert: "Okenn kont ajan pa jwenn ak email sa a."
      end

      CitizenOtpService.new(user).generate!(
        fingerprint: request_fingerprint,
        mailer: Ajan::AjanMailer
      )

      session[:pending_agent_id] = user.id

      redirect_to ajan_verify_otp_path(email: user.email),
                  notice: "Nou voye yon kòd yon fwa nan email ou."
    rescue => e
      Rails.logger.error("[Ajan::Sessions] OTP generation failed: #{e.message}")
      redirect_to ajan_otp_sign_in_path,
                  alert: "Nou pa t kapab voye kòd la. Eseye ankò."
    end

    # GET/POST /ajan/verifye-kod
    def verify_otp
      user = User.find_by(id: session[:pending_agent_id])

      unless user
        return redirect_to ajan_otp_sign_in_path,
                           alert: "Sesyon w fini. Rekòmanse tanpri."
      end

      if request.post? && params[:otp].present?
        if CitizenOtpService.new(user).verify!(params[:otp].to_s, fingerprint: request_fingerprint)
          sign_in_agent(user)
        else
          flash.now[:alert] = "Kòd la pa valid oswa li ekspire."
          render :verify_otp, status: :unprocessable_entity
        end
      else
        render :verify_otp, locals: { email: user.email }
      end
    end

    # POST /ajan/voye-kod
    def resend_otp
      user = User.find_by(id: session[:pending_agent_id])

      unless user
        return redirect_to ajan_otp_sign_in_path,
                           alert: "Sesyon w fini. Rekòmanse tanpri."
      end

      CitizenOtpService.new(user).generate!(
        fingerprint: request_fingerprint,
        mailer: Ajan::AjanMailer
      )
      flash[:notice] = "Nouvo kòd voye nan email ou."
      redirect_to ajan_verify_otp_path(email: user.email)
    rescue => e
      Rails.logger.error("[Ajan::Sessions] OTP resend failed: #{e.message}")
      redirect_to ajan_verify_otp_path(email: user&.email),
                  alert: "Nou pa t kapab voye kòd la ankò. Eseye ankò."
    end

    # DELETE /ajan/dekonekte
    def destroy
      signed_out = sign_out(resource_name)
      session.delete(:ajan_user_id)
      flash[:notice] = "Ou dekonekte." if signed_out
      redirect_to after_sign_out_path_for(resource_name)
    end

    protected

    def after_sign_in_path_for(_resource)
      ajan_tablo_path
    end

    def after_sign_out_path_for(_resource_or_scope)
      ajan_otp_sign_in_path
    end

    private

    # Post-OTP sign-in: enforce the remaining gates (partner + BonID)
    # then sign in the :agent scope. Role check already ran in create_otp.
    def sign_in_agent(user)
      unless user.partner_id.present?
        session.delete(:pending_agent_id)
        return redirect_to ajan_otp_sign_in_path,
                           alert: "Ou poko afekte nan yon ekip. Mande administratè ou yon envitasyon."
      end

      unless user.bonid_verified?
        session.delete(:pending_agent_id)
        return redirect_to ajan_otp_sign_in_path,
                           alert: "BonID ou dwe verifye anvan ou ka antre nan Pòtay Ajan."
      end

      sign_in(:agent, user)
      # Mirror the agent identity into a plain session key so Ajan::ApplicationController
      # can resolve the current agent even when warden's :agent scope fails to
      # rehydrate across redirects (seen in practice on tunnelled ngrok sessions).
      session[:ajan_user_id] = user.id
      session.delete(:pending_agent_id)

      redirect_to after_sign_in_path_for(user),
                  notice: "Byenveni, #{user.first_name.presence || user.full_name}."
    rescue => e
      Rails.logger.error("[Ajan::Sessions] sign-in failed: #{e.class} - #{e.message}")
      redirect_to ajan_otp_sign_in_path,
                  alert: "Koneksyon echwe. Eseye ankò."
    end

    def agent_account?(user)
      return false unless user

      agent_keys = ::GovernmentRoleConstants.agent_role_keys
      (user.roles.pluck(:name) & agent_keys).any?
    end

    def request_fingerprint
      "#{request.remote_ip}-#{request.user_agent}"
    end

    def rate_limit_otp_requests
      return if Rails.env.development? || Rails.env.test?

      key = "ajan_otp_attempts:#{request_fingerprint}"
      count = Rails.cache.fetch(key, expires_in: 15.minutes) { 0 }

      if count >= 10
        render plain: "Twòp eseyaj. Tanpri tann kèk minit.", status: :too_many_requests
        return
      end

      Rails.cache.write(key, count + 1, expires_in: 15.minutes)
    end
  end
end
