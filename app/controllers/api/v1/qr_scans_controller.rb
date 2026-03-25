# app/controllers/api/v1/qr_scans_controller.rb
module Api
  module V1
    class QrScansController < Api::V1::BaseController
      before_action :authenticate_api_key!

      # POST /api/v1/qr_scan
      def create
        qr_data = params[:qr_data].to_s.strip
        return render json: { error: "Missing QR data" }, status: :bad_request if qr_data.blank?

        payload = decode_qr(qr_data)
        return render json: { status: "invalid", message: "Malformed QR payload" }, status: :unprocessable_entity unless payload.is_a?(Hash)

        # Ed25519 v2 payload — cryptographic verification
        if payload["v"].to_i == 2 && payload["sig"].present?
          result = BonidQrSigner.verify(payload)

          unless result == :valid
            return render json: {
              status: "invalid",
              message: "QR verification failed: #{result}",
              version: 2
            }, status: :unauthorized
          end

          bonid = payload["sub"]
        else
          # Legacy HMAC payload
          bonid = payload["bonid"]
        end

        user = User.find_by(bonid: bonid)

        if user&.verified_identity_submission
          render json: { status: "verified", bonid: user.bonid, version: payload["v"] || 1 }, status: :ok
        else
          render json: { status: "invalid", message: "BonID not verified or invalid" }, status: :not_found
        end
      rescue JSON::ParserError
        render json: { status: "invalid", message: "Malformed QR payload" }, status: :unprocessable_entity
      end

      private

      def decode_qr(qr_data)
        JSON.parse(Base64.decode64(qr_data))
      rescue
        # Try parsing as raw JSON (not Base64-encoded)
        JSON.parse(qr_data) rescue nil
      end
    end
  end
end
