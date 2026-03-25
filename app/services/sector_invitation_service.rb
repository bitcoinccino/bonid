# app/services/sector_invitation_service.rb
module SectorInvitationService
  DEFAULT_MODEL = User
  DEFAULT_ROLE  = "Member"

  # 🔑 Aliases to unify sector naming
  ALIASES = {
    "embassy"   => "embassy_services",
    "hospital"  => "healthcare",
    "school"    => "education"
  }.freeze

  # === Model Map (which model to use) ===
  MODEL_MAP = {
    "law_enforcement"          => { admin: User, default: Officer },
    "embassy_services"         => { default: User },
    "healthcare"               => { default: User },
    "education"                => { default: User },
    "online_education"         => { default: User },
    "media_and_entertainment"  => { default: User },
    "public_health_campaigns"  => { default: User },
    "social_services"          => { default: User },
    "disaster_relief"          => { default: User },
    "ngos"                     => { default: User },
    "cultural_heritage"        => { default: User },
    "fintech"                  => { default: User },
    "cryptocurrency"           => { default: User },
    "banking"                  => { default: User },
    "insurance"                => { default: User },
    "retail"                   => { default: User },
    "hospitality"              => { default: User },
    "market_commerce"          => { default: User },
    "food_and_beverage"        => { default: User },
    "art_and_craft"            => { default: User },
    "tourism"                  => { default: User },
    "agriculture"              => { default: User },
    "fisheries"                => { default: User },
    "energy"                   => { default: User },
    "environmental_conservation" => { default: User },
    "sanitation"               => { default: User },
    "mining_and_resources"     => { default: User },
    "public_transport"         => { default: User },
    "utilities"                => { default: User },
    "telecommunications"       => { default: User },
    "real_estate"              => { default: User },
    "human_resources"          => { default: User },
    "legal"                    => { default: User },
    "adult_services"           => { default: User },
    "youth_and_sports"         => { default: User }
  }.freeze

  # === Role Map (labels for invites) ===
  ROLE_MAP = {
    "law_enforcement"          => { admin: "Partner Admin", default: "Officer" },
    "embassy_services"         => { default: "Delegate" },
    "healthcare"               => { default: "Staff" },
    "education"                => { default: "Educator" },
    "online_education"         => { default: "Educator" },
    "media_and_entertainment"  => { default: "Contributor" },
    "public_health_campaigns"  => { default: "Staff" },
    "fintech"                  => { default: "Representative" },
    "cryptocurrency"           => { default: "Representative" },
    "banking"                  => { default: "Representative" },
    "insurance"                => { default: "Representative" },
    "government"               => { default: "Agent" },
    "local_governance"         => { default: "Agent" },
    "customs_service"          => { default: "Agent" },
    "border_control"           => { default: "Agent" },
    "electoral_systems"        => { default: "Agent" },
    "community_organizations"  => { default: "Volunteer" },
    "social_services"          => { default: "Volunteer" },
    "disaster_relief"          => { default: "Volunteer" },
    "ngos"                     => { default: "Volunteer" },
    "cultural_heritage"        => { default: "Volunteer" },
    "retail"                   => { default: "Merchant" },
    "hospitality"              => { default: "Merchant" },
    "market_commerce"          => { default: "Merchant" },
    "food_and_beverage"        => { default: "Merchant" },
    "art_and_craft"            => { default: "Merchant" },
    "tourism"                  => { default: "Merchant" },
    "agriculture"              => { default: "Field Agent" },
    "fisheries"                => { default: "Field Agent" },
    "energy"                   => { default: "Field Agent" },
    "environmental_conservation" => { default: "Field Agent" },
    "sanitation"               => { default: "Field Agent" },
    "mining_and_resources"     => { default: "Field Agent" },
    "public_transport"         => { default: "Service Agent" },
    "utilities"                => { default: "Service Agent" },
    "telecommunications"       => { default: "Service Agent" },
    "real_estate"              => { default: "Service Agent" },
    "human_resources"          => { default: "Specialist" },
    "legal"                    => { default: "Specialist" },
    "adult_services"           => { default: "Performer" },
    "youth_and_sports"         => { default: "Coach" }
  }.freeze

  # === Normalize a sector string
  def self.normalize_sector(sector)
    key = sector.to_s.strip.downcase
    ALIASES[key] || key
  end

  # === Resolve which model is used for a sector
  def self.resolve_user_model_for_sector(sector, role: :default)
    normalized = normalize_sector(sector)
    MODEL_MAP.dig(normalized, role) ||
      MODEL_MAP.dig(normalized, :default) ||
      DEFAULT_MODEL
  end

  # === Resolve which role label to use
  def self.invite_role_for_sector(sector, role: :default)
    normalized = normalize_sector(sector)
    ROLE_MAP.dig(normalized, role) ||
      ROLE_MAP.dig(normalized, :default) ||
      DEFAULT_ROLE
  end

  # === NEW: Law enforcement extras (ranks/units)
  def self.extra_attributes_for_sector(sector)
    normalized = normalize_sector(sector)
    return {} unless normalized == "law_enforcement"

    {
      ranks: OfficerConstants::RANKS,
      units: OfficerConstants::UNIT_OPTIONS
    }
  end
end
