# frozen_string_literal: true
#
# app/controllers/partner_portal/law_enforcement/base_controller.rb
#
# Base controller for all PartnerPortal::LawEnforcement:: controllers.
# Extends PartnerPortal::BaseController with PNH-specific unit-scoping.
#
# Admin scope derivation (no migration required):
#   1. If the signed-in PartnerAdmin has a linked Officer (same email + partner_id)
#      and that officer's rank is :strategic → admin scope = :full (sees all units)
#   2. If linked officer is :field or :supervisor → admin scope = :unit (own unit only)
#   3. If no linked Officer (admin-only staff) → admin scope = :full (full partner view)
#
# All four law enforcement portal controllers inherit from this class.

module PartnerPortal
  module LawEnforcement
    class BaseController < PartnerPortal::BaseController
      before_action :set_portal_admin_scope

      helper_method :portal_admin_scope, :portal_admin_unit_scoped?, :portal_admin_unit

      private

      # Derives and memoises the portal admin scope (:full or :unit).
      # Delegates to OfficerAccessControl.portal_admin_scope_for.
      def set_portal_admin_scope
        @portal_admin_scope ||= Officer.portal_admin_scope_for(@current_portal_user)
      end

      # Returns :full or :unit
      def portal_admin_scope
        @portal_admin_scope
      end

      # True if the admin is unit-scoped (non-strategic linked officer)
      def portal_admin_unit_scoped?
        @portal_admin_scope == :unit
      end

      # Returns the unit_name of the linked officer, or nil if full-scope admin.
      # Memoised per request.
      def portal_admin_unit
        @portal_admin_unit ||= begin
          officer = Officer.officer_for_admin(@current_portal_user)
          officer&.unit_name
        end
      end

      # Applies unit filter to an incident report relation when the admin is unit-scoped.
      # Full-scope admins receive the base relation unchanged.
      #
      # Usage: apply_portal_incident_scope(@partner.incident_reports)
      def apply_portal_incident_scope(base_relation)
        return base_relation unless portal_admin_unit_scoped? && portal_admin_unit.present?

        officer_ids = Officer.where(
          partner_id: @current_partner.id,
          unit_name:  portal_admin_unit
        ).pluck(:id)

        base_relation.where(officer_id: officer_ids)
      end

      # Applies unit filter to an officer relation when the admin is unit-scoped.
      # Full-scope admins receive the base relation unchanged.
      #
      # Usage: apply_portal_officer_scope(@partner.officers)
      def apply_portal_officer_scope(base_relation)
        return base_relation unless portal_admin_unit_scoped? && portal_admin_unit.present?

        base_relation.where(unit_name: portal_admin_unit)
      end

      # Guard: raises an access denied redirect if the admin is unit-scoped
      # and the given officer belongs to a different unit.
      # Returns true if allowed, false + redirect if denied.
      def enforce_unit_access_on_officer!(officer)
        return true if portal_admin_scope == :full
        if officer.unit_name != portal_admin_unit
          redirect_to partner_portal_law_enforcement_officers_path,
                      alert: "Accès refusé. Vous ne pouvez gérer que les agents de votre unité."
          return false
        end
        true
      end
    end
  end
end
