# app/controllers/api/v1/discovery_controller.rb
module Api
  module V1
    class DiscoveryController < Api::V1::BaseController
      skip_before_action :authenticate_partner_or_token!

      def show
        render json: {
          issuer: root_url.chomp("/"),
          authorization_endpoint: oauth_authorize_url,
          token_endpoint: api_v1_oauth_token_url,
          userinfo_endpoint: api_v1_userinfo_url,
          jwks_uri: api_v1_jwks_url,
          scopes_supported: %w[openid email profile address physical],
          response_types_supported: [ "code", "token" ],
          grant_types_supported: [ "authorization_code", "refresh_token" ]
        }
      end
    end
  end
end
