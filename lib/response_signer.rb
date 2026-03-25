# lib/response_signer.rb
require "openssl"
require "base64"

module ResponseSigner
  # Signs the given payload and attaches a header like:
  #   X-BonID-Signature: <HMAC>
  #
  # Partners can use the same secret key to verify the response integrity.

  def sign_response(payload)
    secret = ENV["BONID_API_SECRET"] || "development_secret_key"
    digest = OpenSSL::Digest.new("sha256")

    # Create the signature using HMAC
    signature = OpenSSL::HMAC.hexdigest(digest, secret, payload.to_json)

    # Add the header to the HTTP response
    response.set_header("X-BonID-Signature", signature)

    # (Optional) return the signature for debugging/logging
    signature
  end
end
