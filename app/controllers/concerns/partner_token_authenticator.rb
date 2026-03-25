# frozen_string_literal: true

module PartnerTokenAuthenticator
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_partner_or_token!
    attr_reader :current_partner
  end

  private

  # -------------------------------------------------------------------
  # ✅ Unified Partner Authentication (API key or OAuth token)
  # -------------------------------------------------------------------
  def authenticate_partner_or_token!
    api_key_header = request.headers["X-Partner-Api-Key"]
    bearer_header  = request.headers["Authorization"]&.to_s

    if api_key_header.present?
      authenticate_with_api_key!(api_key_header)
    elsif bearer_header&.start_with?("Bearer ")
      authenticate_with_oauth_token!(bearer_header.split(" ").last)
    else
      render_unauthorized!("Missing authentication credentials.")
    end
  end

  # -------------------------------------------------------------------
  # 🔑 API Key Path (Legacy)
  # -------------------------------------------------------------------
  def authenticate_with_api_key!(api_key)
    # Fast path: SHA256 digest lookup
    sha_digest = Digest::SHA256.hexdigest(api_key)
    partner = Partner.find_by(api_key_digest: sha_digest)

    # Slow fallback: BCrypt digests
    if partner.nil?
      partner = Partner.where.not(api_key_digest: nil).detect do |p|
        digest = p.api_key_digest.to_s
        next false if digest.blank?
        next false unless digest.start_with?("$2")

        begin
          BCrypt::Password.new(digest).is_password?(api_key)
        rescue BCrypt::Errors::InvalidHash
          false
        end
      end
    end

    unless partner&.verified_at?
      return render_unauthorized!("Invalid or unverified API key.")
    end
    @current_partner = partner
  end

  # -------------------------------------------------------------------
  # 🪪 OAuth Bearer Token Path
  # -------------------------------------------------------------------
  def authenticate_with_oauth_token!(token)
    payload = decode_access_token(token)
    partner = Partner.find_by(id: payload[:partner_id])
    unless partner&.verified_at?
      return render_unauthorized!("Partner not verified or missing.")
    end

    if Time.current > payload[:exp].to_time
      return render_unauthorized!("Access token expired.")
    end

    @current_partner = partner
  rescue JWT::DecodeError, JWT::VerificationError => e
    Rails.logger.error("OAuth token decode failed: #{e.message}")
    render_unauthorized!("Invalid access token.")
  end

  # -------------------------------------------------------------------
  # 🔍 Decode JWT Access Token
  # -------------------------------------------------------------------
  def decode_access_token(token)
    secret = Rails.application.credentials.dig(:jwt, :secret_key_base) || ENV["JWT_SECRET_KEY"]
    decoded = JWT.decode(token, secret, true, algorithm: "HS256")
    decoded.first.deep_symbolize_keys
  end

  # -------------------------------------------------------------------
  # 🚫 Unified Error Response
  # -------------------------------------------------------------------
  def render_unauthorized!(message)
    render json: { error: message, status: 401 }, status: :unauthorized
  end
end
