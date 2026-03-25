# app/controllers/api/v1/moncash_controller.rb
module Api
  module V1
    class MoncashController < ApplicationController

          if respond_to?(:skip_before_action)

            if respond_to?(:skip_before_action)

              if respond_to?(:skip_before_action)

                if respond_to?(:skip_before_action)

                      if defined?(verify_authenticity_token) && respond_to?(:skip_before_action)
                skip_before_action :verify_authenticity_token
              end
      
            end
  
          end
  
        end
  
      end
  

      def sync_wallet
        user = Citizen.find_by(email: params[:email]) # or bonid
        return render json: { error: "User not found" }, status: :not_found unless user

        MoncashAdapter.sync(user, params[:wallet])
        render json: { success: true, message: "MonCash profile synced" }
      rescue => e
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
