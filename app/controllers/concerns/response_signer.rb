# app/controllers/concerns/response_signer.rb
module ResponseSigner
  extend ActiveSupport::Concern

  def sign_response(payload)
    timestamp = Time.now.utc.iso8601
    body      = payload.is_a?(String) ? payload : payload.to_json
    secret    = @current_partner&.api_key_digest || Rails.application.credentials.dig(:bonid, :signature_secret)

    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}:#{body}")

    response.headers["X-Signature"] = signature
    response.headers["X-Timestamp"] = timestamp
  rescue => e
    Rails.logger.error("[ResponseSigner] Failed to sign response: #{e.message}")
  end
end
