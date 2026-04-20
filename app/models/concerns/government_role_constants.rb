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
# ONACA exception (4 roles): two specialized agent sub-roles per Haiti's Civil Law system:
#   partner_agent_surveyor → Apantè (technical data, parcel mapping)
#   partner_agent_notary   → Notè (legal docs, validates ownership for admin review)
#
# Banking exception (4 roles): three specialized sub-roles for bank operations:
#   bank_agent      → Ajan Bank (bank agent/representative)
#   bank_supervisor → Sipèvizè Bank (bank supervisor)
#   bank_teller     → Kesye (teller/cashier)
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
  # Banking: admin + bank_agent + bank_teller + bank_supervisor (4 roles)
  # Default (NGO, etc.): admin + agent + supervisor (3 roles)
  # ============================================================
  AGENCY_ROLES = {
    "immigration" => [
      { key: "partner_admin",      label: "Administratè",      description: "Jere kle API, wè analitik",                          requirement: "verified_bonid + employee_id",                tier: :strategic },
      { key: "partner_agent",      label: "Ajan Imigrasyon",   description: "Scan BonID, konsome resi, trete paspò",               requirement: "verified_bonid + officer_id (IMM-OFF-XXXX)",  tier: :field },
      { key: "partner_supervisor", label: "Sipèvizè",          description: "Revize odit, make anomali",                           requirement: "verified_bonid + supervisor_clearance",       tier: :supervisor }
    ],
    "onaca" => [
      { key: "partner_admin",            label: "Administratè",  description: "Jere pòtay, kle API, envite ekip" },
      { key: "partner_agent_surveyor",   label: "Apantè",         description: "Done teknik, apantaj teren, nimewo pasèl" },
      { key: "partner_agent_notary",     label: "Notè",            description: "Dokiman legal, valide pwopriyete pou revizyon administratè" },
      { key: "partner_supervisor",       label: "Sipèvizè",       description: "Revize aktivite ajan, make anomali" }
    ],
    "banking" => [
      { key: "partner_admin",   label: "Administratè",    description: "Jere pòtay, kle API, envite ekip" },
      { key: "bank_agent",      label: "Ajan Bank",        description: "Reprezantan bank, jere kliyan ak operasyon" },
      { key: "bank_teller",     label: "Kesye",             description: "Kesye ki resevwa depo, retrè, ak skan BonID" },
      { key: "bank_supervisor", label: "Sipèvizè Bank",    description: "Sipèvize operasyon kesye ak ajan, make anomali" }
    ],
    "cep" => [
      { key: "partner_admin", label: "Administratè",     description: "Jere sistèm elektoral, kle API, envite ekip", requirement: "verified_bonid + employee_id", tier: :strategic },
      { key: "partner_agent", label: "Ajan Enskripsyon", description: "Enskri elektè, verifye idantite nan BEC",      requirement: "verified_bonid + cep_badge",   tier: :field }
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
  BANKING_SECTORS = %w[
    banking commercial_bank microfinance credit_union money_transfer
    mobile_wallet payment_processor remittance fintech
  ].freeze

  def self.roles_for(sector)
    key = sector.to_s.downcase
    key = "banking" if BANKING_SECTORS.include?(key)
    AGENCY_ROLES[key] || base_roles(sector)
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
    roles_for(sector).map { |r| [ "#{r[:label]} — #{r[:description]}", r[:key] ] }
  end
end
