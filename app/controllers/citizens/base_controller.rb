# app/controllers/citizens/base_controller.rb
module Citizens
  class BaseController < ApplicationController
    before_action :authenticate_citizen!
    before_action :require_citizen!
    layout "citizen"

    private

    def require_citizen!
      unless current_citizen&.has_role?(:citizen)
        Rails.logger.warn "[require_citizen!] FAILED — current_citizen=#{current_citizen&.id || 'nil'}, " \
                          "roles=#{current_citizen&.roles&.pluck(:name)&.join(',') || 'none'}, " \
                          "path=#{request.path}, session_keys=#{session.keys.join(',')}"
        sign_out(:citizen)
        redirect_to citizens_otp_sign_in_path,
                    alert: "Log in as or sign up as a citizen."
      end
    end
  end
end
