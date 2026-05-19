
module PartnersHelper
  ROLE_MAP = {
    law_enforcement: "Officer",
    embassy_services: "Delegate",
    education: "Educator",
    online_education: "Educator",
    media_and_entertainment: "Contributor",
    public_health_campaigns: "Staff",
    healthcare: "Staff",
    fintech: "Representative",
    cryptocurrency: "Representative",
    banking: "Representative",
    insurance: "Representative",
    government: "Agent",
    local_governance: "Agent",
    customs_service: "Agent",
    border_control: "Agent",
    electoral_systems: "Agent",
    community_organizations: "Volunteer",
    social_services: "Volunteer",
    disaster_relief: "Volunteer",
    ngos: "Volunteer",
    cultural_heritage: "Volunteer",
    retail: "Merchant",
    hospitality: "Merchant",
    market_commerce: "Merchant",
    food_and_beverage: "Merchant",
    art_and_craft: "Merchant",
    tourism: "Merchant",
    agriculture: "Field Agent",
    fisheries: "Field Agent",
    energy: "Field Agent",
    environmental_conservation: "Field Agent",
    sanitation: "Field Agent",
    mining_and_resources: "Field Agent",
    public_transport: "Service Agent",
    utilities: "Service Agent",
    telecommunications: "Service Agent",
    real_estate: "Service Agent",
    human_resources: "Specialist",
    legal: "Specialist",
    adult_services: "Performer",
    youth_and_sports: "Coach"
  }.freeze

  def invite_role_for_sector(sector)
    ROLE_MAP[sector.to_s.strip.downcase.to_sym] || "Member"
  end

  # Returns appropriate icon class for a partner sector
  def sector_icon(sector)
    case sector.to_s.downcase
    when "banking", "fintech", "cryptocurrency", "commercial_bank", "microfinance", "credit_union",
         "money_transfer", "mobile_wallet", "payment_processor", "crypto_exchange", "remittance"
      "ri-bank-line"
    when "healthcare", "hospital", "public_health_campaigns"
      "ri-hospital-line"
    when "law_enforcement", "border_control"
      "ri-shield-star-line"
    when "embassy_services", "government", "local_governance"
      "ri-government-line"
    when "telecommunications", "utilities"
      "ri-signal-tower-line"
    when "insurance"
      "ri-umbrella-line"
    when "education", "online_education"
      "ri-graduation-cap-line"
    when "retail", "market_commerce"
      "ri-store-2-line"
    when "hospitality", "tourism"
      "ri-hotel-line"
    when "real_estate"
      "ri-home-3-line"
    when "agriculture", "fisheries"
      "ri-plant-line"
    when "legal"
      "ri-scales-3-line"
    when "ngos", "community_organizations", "social_services"
      "ri-hand-heart-line"
    when "media_and_entertainment"
      "ri-film-line"
    when "public_transport"
      "ri-bus-line"
    when "energy", "environmental_conservation"
      "ri-leaf-line"
    else
      "ri-building-2-line"
    end
  end

  # Returns array of benefits for each sector - more descriptive and compelling
  # Returns the parent group name for a given sector value
  # e.g. "mobile_wallet" => "Fintech & Mobile Money", "pnh" => "Law Enforcement"
  # Returns the human label for a single sector value in the current
  # locale. Lookup chain:
  #   1. i18n key main.partners.sectors.<slug>
  #   2. PartnerSectorConstants::SECTOR_LABEL_OVERRIDES (English overrides)
  #   3. Title-cased slug ("commercial_bank" -> "Commercial Bank")
  def sector_label_translated(value)
    slug = value.to_s.downcase
    i18n_label = I18n.t("main.partners.sectors.#{slug}", default: nil)
    return i18n_label if i18n_label.present?

    PartnerSectorConstants.human_sector_label(slug)
  end

  # Drop-in replacement for the inline grouping in partners.html.erb.
  # Returns [[group_label, [[option_label, slug], ...]], ...] suitable
  # for grouped_options_for_select. Both group and option labels are
  # translated per current locale; falls back gracefully when keys are
  # missing.
  def translated_sector_filter_groups
    PartnerSectorConstants::SECTORS.map do |group, sectors|
      slug = group.parameterize(separator: "_")
      group_label = I18n.t("main.partners.sector_groups.#{slug}", default: group)
      [
        group_label,
        sectors.map { |s| [sector_label_translated(s), s] }
      ]
    end
  end

  def sector_group_label(sector)
    sector_key = sector.to_s.downcase
    group = PartnerSectorConstants::SECTORS.find { |_g, values| values.include?(sector_key) }&.first
    return sector_key.tr("_", " ").split.map(&:capitalize).join(" ") if group.blank?

    # Slugify the canonical English group key ("Fintech & Mobile Money"
    # -> "fintech_mobile_money") and look it up. Fall back to the
    # original English group name if no translation is registered.
    slug = group.parameterize(separator: "_")
    I18n.t("main.partners.sector_groups.#{slug}", default: group)
  end

  # Maps every supported sector value to the i18n key group that holds
  # its benefit bullets. Update here when adding a new sector value.
  PARTNER_BENEFIT_GROUPS = {
    # banking
    "banking" => "banking", "fintech" => "banking", "commercial_bank" => "banking",
    "microfinance" => "banking", "credit_union" => "banking", "money_transfer" => "banking",
    # mobile wallet & crypto
    "mobile_wallet" => "mobile_wallet", "payment_processor" => "mobile_wallet",
    "crypto_exchange" => "mobile_wallet", "remittance" => "mobile_wallet",
    # healthcare
    "healthcare" => "healthcare", "hospital" => "healthcare", "public_health_campaigns" => "healthcare",
    "clinic" => "healthcare", "pharmacy" => "healthcare", "lab" => "healthcare",
    "medical_insurance" => "healthcare",
    # law enforcement
    "law_enforcement" => "law_enforcement", "border_control" => "law_enforcement", "pnh" => "law_enforcement",
    # cep
    "cep" => "cep",
    # dgi
    "dgi" => "dgi",
    # oni
    "oni" => "oni",
    # embassy / diplomatic
    "embassy" => "embassy", "consulate" => "embassy", "international_org" => "embassy",
    "embassy_services" => "embassy",
    # government
    "government" => "government", "local_governance" => "government", "onaca" => "government",
    "archives_nationales" => "government", "mairie" => "government", "municipality" => "government",
    "ministry" => "government", "customs" => "government", "immigration" => "government",
    # telecoms
    "telecommunications" => "telecommunications", "mobile_carrier" => "telecommunications",
    "isp" => "telecommunications", "cable_provider" => "telecommunications",
    # insurance
    "insurance" => "insurance",
    # education
    "education" => "education", "online_education" => "education",
    # retail
    "retail" => "retail", "market_commerce" => "retail",
    # hospitality
    "hospitality" => "hospitality", "tourism" => "hospitality",
    # real estate
    "real_estate" => "real_estate",
    # ngos
    "ngos" => "ngos", "community_organizations" => "ngos", "social_services" => "ngos",
    "disaster_relief" => "ngos",
    # legal
    "legal" => "legal",
    # cryptocurrency
    "cryptocurrency" => "cryptocurrency"
  }.freeze

  def partner_benefits(sector)
    group = PARTNER_BENEFIT_GROUPS[sector.to_s.downcase] || "default"
    bullets = I18n.t("main.partners.benefits.#{group}", default: nil)

    # Fall back to the default group if the translation key is missing
    # (e.g. a new sector added before its YAML entry).
    bullets = I18n.t("main.partners.benefits.default", default: []) if bullets.blank?

    Array(bullets)
  end

end
