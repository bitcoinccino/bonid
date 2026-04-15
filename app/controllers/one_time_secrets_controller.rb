# frozen_string_literal: true

# Public controller — no auth required.
# The token in the URL IS the authentication.
class OneTimeSecretsController < ApplicationController
  layout "citizen_auth"
  skip_before_action :authenticate_user!, raise: false

  def show
    @secret = OneTimeSecret.find_by(token: params[:token])

    unless @secret
      @error = "This secret link is invalid."
      return render :show, status: :not_found
    end

    if @secret.viewed?
      @error = "This secret has already been viewed and is no longer available."
      return render :show, status: :gone
    end

    if @secret.expired?
      @error = "This secret link has expired."
      return render :show, status: :gone
    end

    # Reveal the secret (one-time only)
    @payload = @secret.reveal!(ip_address: request.remote_ip)
    @partner = @secret.partner
  end
end
