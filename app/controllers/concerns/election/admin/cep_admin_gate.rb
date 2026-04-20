# frozen_string_literal: true

# Election::Admin::CepAdminGate — access control for CEP Command Center
# pages (election dashboards, BED/BEK CRUD, signing ceremony, etc.).
#
# v1 scope: only platform-level AdminUsers with the Rolify roles below have
# Command Center access. Field roles (partner_agent / Ajan Enskripsyon) work
# exclusively through the partner portal; they never reach this surface.
module Election
  module Admin
    module CepAdminGate
      extend ActiveSupport::Concern

      # Any AdminUser Rolify role that grants CEP command-center access.
      ADMIN_ROLIFY_ROLES = %i[super_admin cep_admin].freeze

      included do
        before_action :require_cep_admin!
      end

      private

      def require_cep_admin!
        return if cep_admin_authorized?

        redirect_to admin_login_path,
                    alert: "Aksè refize. Sèlman administratè CEP ka wè paj sa a."
      end

      def cep_admin_authorized?
        admin = current_admin_user
        return false unless admin
        return false unless admin.respond_to?(:has_role?)

        ADMIN_ROLIFY_ROLES.any? { |r| admin.has_role?(r) }
      end
    end
  end
end
