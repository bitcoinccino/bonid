# frozen_string_literal: true

# Election::Admin::CepAdminGate — access control for CEP Command Center
# pages (election dashboards, BED/BEK CRUD, signing ceremony, etc.).
#
# Auth bridges two role systems BonID already carries:
#
#   1. AdminUser + Rolify (platform-level logins):
#      - `:super_admin`  — Verifyem/BonID platform owners. Full bypass.
#      - `:cep_admin`    — dedicated CEP command-center operator account.
#
#   2. User + ElectionStaffAssignment (CEP org chart):
#      - `cep_council_member`, `cep_dispute_officer` (strategic tier) —
#        the nine-member council + adjudicators with full command-center
#        access.
#      - `cep_supervisor` (supervisor tier) — read-only for field ops.
#
# An AdminUser gains CEP access either by holding the Rolify role directly,
# or by matching (via email) to a `User` record that holds a strategic-tier
# ElectionStaffAssignment on any active election. This lets real CEP staff
# log in through the admin portal without creating duplicate identity, while
# platform operators can carry `:cep_admin` on their AdminUser.
module Election
  module Admin
    module CepAdminGate
      extend ActiveSupport::Concern

      # Any AdminUser Rolify role that grants CEP command-center access.
      ADMIN_ROLIFY_ROLES = %i[super_admin cep_admin].freeze

      # User-side ElectionStaffAssignment roles that grant CEP access when
      # the AdminUser's email matches a User carrying one of these.
      STAFF_ROLES = %w[cep_council_member cep_dispute_officer].freeze

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

        # Fast path: platform Rolify role on the AdminUser itself.
        return true if admin.respond_to?(:has_role?) &&
                       ADMIN_ROLIFY_ROLES.any? { |r| admin.has_role?(r) }

        # Bridge path: the admin's email matches a CEP-assigned User.
        bridge_user = User.find_by(email: admin.email)
        return false unless bridge_user

        ElectionStaffAssignment
          .active
          .where(user_id: bridge_user.id, role: STAFF_ROLES)
          .exists?
      end
    end
  end
end
