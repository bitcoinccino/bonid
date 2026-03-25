# frozen_string_literal: true

# Service to route partner admins to their correct dashboard based on partner sector
class PartnerPortalRouter
  class << self
    # Returns the correct dashboard path for a partner admin based on their partner's sector
    # @param resource [PartnerAdmin] the partner admin user
    # @return [String] the path to redirect to
    def dashboard_path_for(resource)
      return fallback_path unless resource.respond_to?(:partner)

      partner = resource.partner
      return fallback_path unless partner

      case partner.sector&.to_s&.downcase
      when "law_enforcement"
        Rails.application.routes.url_helpers.partner_portal_law_enforcement_dashboard_path
      when "embassy"
        Rails.application.routes.url_helpers.partner_portal_embassy_dashboard_path
      when "bank", "banking"
        Rails.application.routes.url_helpers.partner_portal_banking_dashboard_path
      else
        fallback_path
      end
    rescue StandardError => e
      Rails.logger.error("PartnerPortalRouter error: #{e.message}")
      fallback_path
    end

    private

    def fallback_path
      Rails.application.routes.url_helpers.partner_portal_root_path
    end
  end
end
