module Api
  module V1
    module Oauth
      class AuthorizationsController < ApplicationController
        before_action :authenticate_partner!
        before_action :authenticate_citizen!

        # Step 1: show consent page
        def new
          @oauth_app = OauthApplication.find_by(uid: params[:client_id])
          unless @oauth_app
            render json: { error: "Invalid client_id" }, status: :bad_request
            return
          end

          # Render JSON or HTML consent page depending on API/client type
          render json: { app: @oauth_app.name, scopes: @oauth_app.scopes.split(" ") }
        end

        # Step 2: user grants consent
        def create
          oauth_app = OauthApplication.find_by(uid: params[:client_id])
          return render json: { error: "Invalid client_id" }, status: :bad_request unless oauth_app

          code = OauthAuthorizationCode.create!(
            oauth_application: oauth_app,
            user: current_user,
            redirect_uri: params[:redirect_uri]
          )

          # Redirect back to partner with code
          redirect_to "#{params[:redirect_uri]}?code=#{code.plain_code}&state=#{params[:state]}"
        end

        private

        def authenticate_citizen!
          # Use Devise current_user or BonID login session
          unless current_user&.role == "citizen"
            render json: { error: "Unauthorized" }, status: :unauthorized
          end
        end

        def authenticate_partner!
          # Minimal: verify client_id and API key in headers
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
