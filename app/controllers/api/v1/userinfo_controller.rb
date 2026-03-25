# app/controllers/api/v1/userinfo_controller.rb
module Api
  module V1
    class UserinfoController < Api::V1::BaseController
      skip_before_action :authenticate_partner_or_token!, only: [ :show ]
      before_action :authenticate_bearer_token!

      def show
        citizen = @access_token.citizen
        render json: {
          sub: citizen.id,
          bonid: citizen.bonid,
          first_name: citizen.first_name,
          last_name: citizen.last_name,
          name: "#{citizen.first_name} #{citizen.last_name}".strip,
          email: citizen.email,
          phone: citizen.phone,
          address: citizen.street_address,
          dob: citizen.dob,
          scopes: @access_token.scopes
        }
      end

      private

      def authenticate_bearer_token!
        token_value = request.headers["Authorization"]&.split&.last
        @access_token = OauthAccessToken.find_by(token: token_value)
        @oauth_token  = @access_token  # alias so BaseController stamping can resolve citizen
        render json: { error: "Invalid or expired token" }, status: :unauthorized unless @access_token&.active?
      end
    end
  end
end
