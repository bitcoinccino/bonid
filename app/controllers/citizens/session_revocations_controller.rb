# frozen_string_literal: true

module Citizens
  # "This wasn't me" link from the new-device email. No login required — the
  # signed token IS the authentication (see Citizens::DeviceRecognition).
  #
  # GET shows a confirm button rather than acting, so an email client
  # prefetching the link can't sign anyone out by itself.
  class SessionRevocationsController < ApplicationController
    layout "citizen_auth"
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :authenticate_citizen!, raise: false

    # GET /citizens/sesyon/revoke?token=…
    def show
      @token = params[:token].to_s
      @valid = Citizens::DeviceRecognition.resolve_revoke_token(@token).present?
      response.headers["Cache-Control"] = "no-store"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    # POST /citizens/sesyon/revoke
    def create
      user, device_id = Citizens::DeviceRecognition.resolve_revoke_token(params[:token])
      unless user
        @valid = false
        return render :show, status: :unprocessable_entity
      end

      # Forget the device they flagged so its next sign-in alerts again.
      user.known_devices.where(id: device_id).delete_all
      user.revoke_all_citizen_sessions!
      sign_out(:citizen) if current_citizen&.id == user.id

      Rails.logger.info("[SessionRevocation] user=#{user.id} flagged_device=#{device_id} ip=#{request.remote_ip}")
      render :done
    end
  end
end
