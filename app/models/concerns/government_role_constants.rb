# frozen_string_literal: true

# GovernmentRoleConstants
# =======================
# Sector-specific roles for all partners except PNH/law enforcement.
# PNH uses OfficerConstants (ranks, units, badges).
#
# Base pattern for every sector:
#   partner_admin      → Administratè (manages portal, API keys, invites team)
#   partner_agent      → Ajan (day-to-day operations, sector-specific label)
#   partner_supervisor → Sipèvizè (reviews agent activity, flags anomalies)
#
# ONACA exception: two specialized agent sub-roles per Haiti's Civil Law system:
#   partner_agent_surveyor → Apantè (technical data, parcel mapping)
#   partner_agent_notary   → Notè (legal docs, validates ownership for admin review)
#
# The Ajan label changes per sector but the DB role stays the same.

module GovernmentRoleConstants
  extend ActiveSupport::Concern

  # ============================================================
  # SECTOR-SPECIFIC AGENT LABELS
  # Only the agent label varies — admin and supervisor are universal
  # ============================================================
  AGENT_LABELS = {
    "dgi"         => "Ajan Kesye",
    "immigration" => "Ajan Imigrasyon",
    "oni"         => "Ajan Idantifikasyon",
    "cep"         => "Ajan Enskripsyon",
    "customs"     => "Ajan Ladwàn",
    "ministry"    => "Ajan",
    "mairie"      => "Ajan",
    "municipality"=> "Ajan",
    "archives_nationales" => "Ajan Achiv"
  }.freeze

  DEFAULT_AGENT_LABEL = "Ajan"

  # ============================================================
  # ROLES PER SECTOR
  # Most sectors: admin + agent + supervisor (3 roles)
  # ONACA: admin + surveyor + notary + supervisor (4 roles)
  # Default (banking, NGO, etc.): admin + agent + supervisor (3 roles)
  # ============================================================
  AGENCY_ROLES = {
    "onaca" => [
      { key: "partner_admin",            label: "Administratè",  description: "Jere pòtay, kle API, envite ekip" },
      { key: "partner_agent_surveyor",   label: "Apantè",         description: "Done teknik, apantaj teren, nimewo pasèl" },
      { key: "partner_agent_notary",     label: "Notè",            description: "Dokiman legal, valide pwopriyete pou revizyon administratè" },
      { key: "partner_supervisor",       label: "Sipèvizè",       description: "Revize aktivite ajan, make anomali" }
    ]
  }.freeze

  # ============================================================
  # BASE ROLES (used by every sector except ONACA)
  # ============================================================
  def self.base_roles(sector)
    agent_label = AGENT_LABELS[sector.to_s.downcase] || DEFAULT_AGENT_LABEL

    [
      { key: "partner_admin",      label: "Administratè",  description: "Jere pòtay, kle API, envite ekip" },
      { key: "partner_agent",      label: agent_label,      description: "Operasyon jounalye" },
      { key: "partner_supervisor", label: "Sipèvizè",       description: "Revize aktivite ajan, make anomali" }
    ]
  end

  # ============================================================
  # Helpers
  # ============================================================
  def self.roles_for(sector)
    AGENCY_ROLES[sector.to_s.downcase] || base_roles(sector)
  end

  def self.role_label(sector, key)
    role = roles_for(sector).find { |r| r[:key] == key.to_s }
    role ? role[:label] : key.to_s.titleize
  end

  def self.valid_role_keys_for(sector)
    roles_for(sector).map { |r| r[:key] }
  end

  # For form dropdowns: [["Administratè — Jere pòtay...", "partner_admin"], ...]
  def self.role_options_for(sector)
    roles_for(sector).map { |r| ["#{r[:label]} — #{r[:description]}", r[:key]] }
  end
end
