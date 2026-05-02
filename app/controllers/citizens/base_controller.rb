# app/controllers/citizens/base_controller.rb
module Citizens
  class BaseController < ApplicationController
    before_action :authenticate_citizen!
    before_action :require_citizen!
    before_action :require_diaspora_answer!
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

    # One-question gate: until the citizen has told us whether they live
    # in Haiti or abroad, every protected page bounces to the onboarding
    # splash. The OnboardingController itself skips this filter so the
    # redirect doesn't loop. Settings + sign-out also bypass so the user
    # always has an escape hatch.
    def require_diaspora_answer!
      return if current_citizen.nil?
      return unless current_citizen.is_diaspora.nil?
      return if request.path == citizens_onboarding_path
      return if request.path == citizens_settings_path
      return unless request.format.html?

      # Auto-resolve for citizens who predate this gate: if they already have
      # an address (which they do once verified or once they've filled their
      # profile), infer is_diaspora from address.country and skip the splash.
      # The onboarding question is only meaningful for fresh signups who
      # haven't told us where they live yet.
      addr_country = current_citizen.address&.country.to_s.strip
      if addr_country.present?
        haiti = %w[HT HAITI].include?(addr_country.upcase)
        current_citizen.update_columns(is_diaspora: !haiti)
        return
      end

      session[:after_onboarding_redirect_to] = request.fullpath if request.get?
      redirect_to citizens_onboarding_path
    end
  end
end
