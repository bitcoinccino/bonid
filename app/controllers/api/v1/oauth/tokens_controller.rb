module Api
  module V1
    module Oauth
      class TokensController < ApplicationController
        before_action :authenticate_partner!

        def create
          oauth_app = OauthApplication.find_by(uid: params[:client_id])
          return render json: { error: "Invalid client_id" }, status: :bad_request unless oauth_app

          code = OauthAuthorizationCode.find_by_code(params[:code])
          unless code&.valid_code?(params[:code])
            return render json: { error: "Invalid or expired code" }, status: :unauthorized
          end

          token = OauthAccessToken.create!(
            oauth_application: oauth_app,
            user: code.user,
            scopes: oauth_app.scopes
          )

          code.mark_used!  # prevent reuse

          render json: {
            access_token: token.plain_token,
            token_type: "Bearer",
            expires_in: (token.expires_at - Time.current).to_i,
            scope: token.scopes
          }
        end

        private

        def authenticate_partner!
          app = OauthApplication.find_by(uid: params[:client_id])
          key = request.headers["X-Partner-Api-Key"]
          unless app && app.partner.authenticate_api_key(key)
            render json: { error: "Invalid partner credentials" }, status: :unauthorized
          end
        end
      end
    end
  end
end
