# frozen_string_literal: true

module PartnerSectorConstants
  extend ActiveSupport::Concern

  # ============================================================
  # Canonical stored values
  # - Keep DB/stored values simple (snake_case, no spaces/apostrophes)
  # - Customize human labels via SECTOR_LABEL_OVERRIDES
  # ============================================================

  SECTORS = {
    "Finance" => %w[
      commercial_bank microfinance credit_union money_transfer
    ],
    "Fintech & Mobile Money" => %w[
      mobile_wallet payment_processor crypto_exchange remittance fintech cryptocurrency
    ],
    "Law Enforcement" => %w[pnh],
    "Government" => %w[
      oni cep dgi onaca archives_nationales mairie municipality ministry customs immigration
    ],
    "Diplomacy" => %w[embassy consulate international_org un_agency],
    "Healthcare" => %w[hospital clinic pharmacy lab medical_insurance],
    "Education" => %w[university school vocational ministry_of_education online_education training_center],
    "Telecom" => %w[mobile_carrier isp cable_provider],
    "Insurance" => %w[health_insurance auto_insurance life_insurance property_insurance],
    "Tourism & Hospitality" => %w[hotel airline tour_operator car_rental hospitality food_and_beverage],
    "NGO & International" => %w[
      un_agency_ngo red_cross usaid development_org humanitarian nonprofit social_services disaster_relief
    ],
    "Real Estate" => %w[notaire property_management construction real_estate],
    "Legal" => %w[law_firm notaire_legal tribunal],
    "Logistics & Transport" => %w[airline_cargo shipping_line courier_service customs_broker public_transport],
    "Gaming & Lottery" => %w[borlette sports_betting casino lottery_admin],
    "Energy & Utilities" => %w[solar_energy propane_gas water_services electricity_provider edh_contractor],
    "Culture & Media" => %w[cultural_heritage media_and_entertainment art_and_craft youth_and_sports],
    "Agriculture & Environment" => %w[
      agriculture fisheries environmental_conservation mining_and_resources
    ],
    "Professional Services" => %w[human_resources legal_services accounting market_commerce retail]
  }.freeze

  # ============================================================
  # Label overrides (display only)
  # ============================================================
  SECTOR_LABEL_OVERRIDES = {
    "pnh"                    => "Police Nationale d'Haiti (PNH)",
    "dcpj"                   => "Direction Centrale de la Police Judiciaire (DCPJ)",
    "bpm"                    => "Brigade de Protection des Mineurs (BPM)",
    "coast_guard"            => "Garde-Cotes d'Haiti",
    "douane"                 => "Administration Generale des Douanes (AGD)",
    "oni"                    => "Office National d'Identification (ONI)",
    "cep"                    => "Conseil Electoral Provisoire (CEP)",
    "dgi"                    => "Direction Generale des Impots (DGI)",
    "onaca"                  => "Office National du Cadastre (ONACA)",
    "archives_nationales"    => "Archives Nationales d'Haiti",
    "mairie"                 => "Mairie / Municipalite",
    "edh_contractor"         => "Electricite d'Haiti (EDH) Contractor",
    "isp"                    => "Internet Service Provider (ISP)",
    "un_agency"              => "UN Agency",
    "un_agency_ngo"          => "UN Agency (NGO)",
    "usaid"                  => "USAID / Development Partner",
    "red_cross"              => "Red Cross / Croix-Rouge",
    "borlette"               => "Borlette (Lottery Operator)",
    "ministry_of_education"  => "Ministere de l'Education Nationale",
    "crypto_exchange"        => "Crypto Exchange / On-Ramp",
    "mobile_wallet"          => "Mobile Wallet (MonCash, Lajan Cash)",
    "payment_processor"      => "Payment Processor",
    "commercial_bank"        => "Commercial Bank",
    "money_transfer"         => "Money Transfer / Wire Service",
    "notaire"                => "Notaire / Notary Public",
    "notaire_legal"          => "Notaire (Legal Services)",
    "medical_insurance"      => "Medical / Health Insurance (Healthcare)",
    "health_insurance"       => "Health Insurance Provider",
    "auto_insurance"         => "Auto Insurance Provider",
    "life_insurance"         => "Life Insurance Provider",
    "property_insurance"     => "Property Insurance Provider",
    "mobile_carrier"         => "Mobile Carrier (Digicel, Natcom)",
    "cable_provider"         => "Cable / TV Provider"
  }.freeze

  # ============================================================
  # Sectors that require a country field (conditional in forms)
  # ============================================================
  COUNTRY_REQUIRED_SECTORS = %w[embassy consulate international_org un_agency].freeze

  # ============================================================
  # Model mapping (what kind of user/account is default per sector)
  # ============================================================
  MODEL_MAP = {
    "law_enforcement"            => { admin: User, default: Officer },
    "pnh"                        => { admin: User, default: Officer }
  }.freeze

  # All sectors not in MODEL_MAP default to { default: User }
  # No need to list every single one

  # ============================================================
  # Helpers
  # ============================================================
  def self.human_sector_label(value)
    key = value.to_s
    return SECTOR_LABEL_OVERRIDES[key] if SECTOR_LABEL_OVERRIDES.key?(key)

    # fallback: "credit_union" => "Credit Union"
    key.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def self.requires_country?(sector)
    COUNTRY_REQUIRED_SECTORS.include?(sector.to_s)
  end

  # ============================================================
  # Flattened dropdown options used by forms
  # e.g. ["Law Enforcement - Police Nationale d'Haiti (PNH)", "pnh"]
  # ============================================================
  SECTOR_OPTIONS = SECTORS.flat_map do |group, items|
    items.map { |sector| [ "#{group} - #{human_sector_label(sector)}", sector ] }
  end.freeze

  included do
    # no-op; keep concern structure clean
  end

  # ============================================================
  # Class methods
  # ============================================================
  class_methods do
    # grouped options per department group (for grouped selects)
    def department_sectors
      SECTORS.transform_values do |values|
        values.map { |v| [ PartnerSectorConstants.human_sector_label(v), v ] }
      end
    end

    # flat options (for normal selects)
    def sector_options
      SECTOR_OPTIONS
    end
  end
end
