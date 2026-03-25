# frozen_string_literal: true

class RoleRedirectService
  class << self
    def after_sign_in_path_for(resource)
      redirect_path_for(resource)
    end

    def after_sign_out_path_for(_resource_or_scope)
      Rails.application.routes.url_helpers.root_path
    end

    def redirect_path_for(resource)
      return "/" if resource.nil?

      role = detect_role(resource)
      log_debug(resource, role)

      case role
      when :admin
        "/admin"
      when :officer
        "/officers/dashboard"
      when :partner_admin
        route_for_partner(resource)
      when :reviewer
        "/admin/identity_submissions"
      when :citizen
        "/citizens/dashboard"
      else
        "/"
      end
    rescue => e
      Rails.logger.error("[RoleRedirectService] Redirect error: #{e.class} - #{e.message}")
      "/"
    end

    private

    # === Partner Admin Sector Routing (Cleaned – no banking)
    def route_for_partner(resource)
      partner = resource.try(:partner)
      sector  = partner&.sector&.downcase

      case sector
      when "hospital", "healthcare"
        "/partner_portal/hospital/dashboard"
      when "embassy", "embassy_services"
        "/partner_portal/embassy/dashboard"
      when "law_enforcement"
        "/partner_portal/law_enforcement/dashboard"
      else
        "/partner_portal/dashboard"
      end
    end

    # === Clean Role Detection
    def detect_role(resource)
      return :admin   if resource.is_a?(AdminUser)
      return :officer if resource.is_a?(Officer)

      roles =
        if resource.respond_to?(:roles)
          resource.roles.pluck(:name).map(&:to_sym)
        elsif resource.respond_to?(:has_role?)
          Role::NAMES.select { |r| resource.has_role?(r.to_sym) }.map(&:to_sym)
        else
          []
        end

      priority = %i[
        admin
        officer
        partner_admin
        reviewer
        citizen
      ]

      roles.find { |r| priority.include?(r) }
    end

    def log_debug(resource, role)
      return unless Rails.env.development?
      Rails.logger.info("[RoleRedirectService] #{resource.class}##{resource.id} → #{role || 'none'}")
    end
  end
end
