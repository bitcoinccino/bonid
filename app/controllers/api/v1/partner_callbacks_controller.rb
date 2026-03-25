# frozen_string_literal: true

module Api
  module V1
    class PartnerCallbacksController < Api::V1::BaseController
      skip_before_action :authenticate_partner_or_token!, only: %i[exchange_token revoke_token]
      protect_from_forgery with: :null_session

      # ===========================================
      # POST /api/v1/oauth/token  (refresh flow)
      # ===========================================
      def exchange_token
        if params[:grant_type] == "refresh_token"
          refresh_flow
        else
          render json: { error: "Unsupported grant_type" }, status: :bad_request
        end
      end

      # ===========================================
      # POST /api/v1/oauth/revoke
      # ===========================================
      def revoke_token
        token_value = request.headers["Authorization"]&.split&.last || params[:token]
        token = OAuthAccessToken.find_by(token: token_value)
        if token&.revoked?
          render json: { status: "already_revoked" }, status: :ok
        elsif token
          token.revoke!
          render json: { status: "revoked", revoked_at: token.revoked_at }, status: :ok
        else
          render json: { error: "Invalid token" }, status: :not_found
        end
      end

      private

      def refresh_flow
        token = OAuthAccessToken.find_by(refresh_token: params[:refresh_token])
        return render json: { error: "Invalid refresh_token" }, status: :unauthorized unless token&.active?

        token.refresh!
        render json: {
          access_token: token.token,
          refresh_token: token.refresh_token,
          expires_in: 3600,
          partner: token.partner.slug
        }, status: :ok
      end
    end
  end
end
