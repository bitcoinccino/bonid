# frozen_string_literal: true
#
# app/models/concerns/officer_access_control.rb
#
# Hybrid unit + rank access control for PNH officers.
# Included in the Officer model. All predicates and scope methods live here.
#
# Three-tier model:
#   Tier 1 — Unit-based data siloing   (UNIT_CRIME_TYPES, BONID_ACCESS_LEVELS)
#   Tier 2 — Rank-based permissions    (RANK_GROUPS → :field / :supervisor / :strategic)
#   Tier 3 — "Need to Know" overrides  (UNIT_ACCESS_SCOPE — JTF, Internal Affairs)
#
# No migration required. Derives everything from existing `rank` and `unit_name` columns.

module OfficerAccessControl
  extend ActiveSupport::Concern

  # ----------------------------------------------------------------
  # RANK GROUP PREDICATES
  # ----------------------------------------------------------------

  # Returns :field, :supervisor, or :strategic based on this officer's rank string.
  # Unknown/blank ranks default to :field (most restrictive).
  def rank_group
    OfficerConstants::RANK_GROUPS[rank.to_s] || :field
  end

  def field_rank?
    rank_group == :field
  end

  def supervisor_rank?
    rank_group == :supervisor
  end

  def strategic_rank?
    rank_group == :strategic
  end

  # ----------------------------------------------------------------
  # UNIT ACCESS PREDICATES
  # ----------------------------------------------------------------

  # True if this officer's unit is restricted (USGPN, USP) — reports from
  # these units are only visible to same-unit officers or strategic rank.
  def restricted_unit?
    OfficerConstants::RESTRICTED_UNITS.include?(unit_name.to_s)
  end

  # Returns "full", "limited", or "standard" based on the officer's unit.
  def bonid_access_level
    OfficerConstants::UNIT_BONID_ACCESS[unit_name.to_s] || "standard"
  end

  def full_bonid_access?
    bonid_access_level == "full"
  end

  def limited_bonid_access?
    bonid_access_level == "limited"
  end

  def standard_bonid_access?
    bonid_access_level == "standard"
  end

  # Returns the crime category keys this officer's unit is authorised to file.
  def authorized_crime_categories
    OfficerConstants::UNIT_CRIME_TYPES[unit_name.to_s] || []
  end

  # Returns the flat list of crime type strings the officer may select.
  # Looks up each category in IncidentReport::CRIME_TYPES (if defined), else returns categories.
  def authorized_crime_types
    cats = authorized_crime_categories
    return cats if cats.empty?

    if defined?(IncidentReport::CRIME_TYPES) && IncidentReport::CRIME_TYPES.is_a?(Hash)
      cats.flat_map { |cat| IncidentReport::CRIME_TYPES[cat.to_sym] || [] }.uniq
    else
      cats
    end
  end

  # True if the officer's unit is authorised to file a given crime_type string.
  # Supervisors and strategic officers are never restricted by crime type.
  def crime_type_authorized?(crime_type)
    return true if supervisor_rank? || strategic_rank?
    return true if authorized_crime_types.empty?  # fallback: allow if no mapping defined
    authorized_crime_types.include?(crime_type.to_s)
  end

  # ----------------------------------------------------------------
  # INCIDENT REPORT VISIBILITY SCOPE
  #
  # Returns an ActiveRecord relation scoped to what this officer may see:
  #   :field      → only own reports
  #   :supervisor → all reports from officers in the same unit + partner
  #   :strategic  → all reports for the partner (+ restricted unit check happens in controller)
  # ----------------------------------------------------------------
  def visible_incident_reports
    base = IncidentReport.where(partner_id: partner_id)

    case rank_group
    when :field
      base.where(officer_id: id)
    when :supervisor
      unit_officer_ids = Officer.where(partner_id: partner_id, unit_name: unit_name).pluck(:id)
      base.where(officer_id: unit_officer_ids)
    when :strategic
      base
    end
  end

  # ----------------------------------------------------------------
  # NEED-TO-KNOW OVERRIDE: Joint Task Force
  #
  # Officers in JTF-authorised units (DCPJ, SWAT) can also see
  # reports whose crime_type matches the JTF trigger list, regardless
  # of which unit filed them. Returns IncidentReport.none for all others.
  # ----------------------------------------------------------------
  def joint_task_force_crime_types
    cfg = OfficerConstants::UNIT_ACCESS_SCOPE[:joint_task_force]
    return [] unless cfg[:authorized_units].include?(unit_name.to_s)
    cfg[:trigger_crime_types]
  end

  def joint_task_force_reports
    jtf_types = joint_task_force_crime_types
    return IncidentReport.none if jtf_types.empty?
    IncidentReport.where(partner_id: partner_id, crime_type: jtf_types)
  end

  # Merges unit-scoped visibility with JTF override.
  # Use this as the single access method in all officer-side controllers.
  def effective_incident_reports
    visible_incident_reports.or(joint_task_force_reports)
  end

  # ----------------------------------------------------------------
  # ANALYTICS SCOPE BOUNDARY
  # ----------------------------------------------------------------

  # Returns the highest analytics scope this officer may request.
  def max_analytics_scope
    case rank_group
    when :field      then "personal"
    when :supervisor then "station"
    when :strategic  then "department"
    end
  end

  # True if the requested scope is at or below this officer's ceiling.
  def analytics_scope_allowed?(requested_scope)
    order = { "personal" => 0, "station" => 1, "department" => 2, "national" => 3 }
    order.fetch(requested_scope.to_s, 0) <= order.fetch(max_analytics_scope, 0)
  end

  # ----------------------------------------------------------------
  # PARTNER PORTAL ADMIN SCOPE (class methods)
  #
  # Used by PartnerPortal::LawEnforcement::BaseController to determine
  # whether a PartnerAdmin has full partner visibility (:full) or is
  # restricted to their linked officer's unit (:unit).
  # ----------------------------------------------------------------
  class_methods do
    # Finds the Officer record linked to a PartnerAdmin by matching email
    # within the same partner. Returns nil if no match found.
    def officer_for_admin(partner_admin)
      return nil unless partner_admin.respond_to?(:partner) && partner_admin.partner.present?
      Officer.find_by(
        partner_id: partner_admin.partner.id,
        email:      partner_admin.email
      )
    end

    # Returns :full or :unit for the given PartnerAdmin.
    #   :full — strategic-rank linked officer OR no linked officer (admin-only staff)
    #   :unit — field or supervisor rank linked officer (restricted to their unit)
    def portal_admin_scope_for(partner_admin)
      officer = officer_for_admin(partner_admin)
      return :full if officer.nil?
      officer.strategic_rank? ? :full : :unit
    end
  end
end
