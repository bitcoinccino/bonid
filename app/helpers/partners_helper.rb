
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
    when "banking", "fintech", "cryptocurrency"
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
  def partner_benefits(sector)
    case sector.to_s.downcase
    when "banking", "fintech"
      [
        "Open bank accounts instantly with your verified BonID",
        "Get faster approval for loans, credit cards & mortgages",
        "Enjoy seamless KYC — no repeated document uploads",
        "Access mobile banking & digital wallets securely"
      ]
    when "healthcare", "hospital", "public_health_campaigns"
      [
        "Skip paperwork — instant patient registration",
        "Access your medical history across any partner hospital",
        "Emergency services can verify your identity immediately",
        "Secure prescription tracking & health records"
      ]
    when "law_enforcement", "border_control"
      [
        "Faster, transparent ID verification during stops",
        "Digital proof of identity — no physical documents needed",
        "Reduced wait times at checkpoints",
        "Audit trail protects both citizens & officers"
      ]
    when "embassy_services", "government", "local_governance"
      [
        "Expedited visa & passport processing",
        "One-click document submission for permits",
        "Reduced bureaucracy for government services",
        "Secure digital signature for official forms"
      ]
    when "telecommunications"
      [
        "Instant SIM card registration & activation",
        "Quick mobile money account setup",
        "Simplified contract signing for phone plans",
        "Secure account recovery without store visits"
      ]
    when "insurance"
      [
        "Faster claims processing with verified identity",
        "Instant policy activation — no paperwork delays",
        "Fraud protection for your policies",
        "Easy beneficiary verification"
      ]
    when "education", "online_education"
      [
        "Streamlined student enrollment & registration",
        "Verified diplomas & certificates",
        "Secure exam identity verification",
        "Easy transcript requests"
      ]
    when "retail", "market_commerce"
      [
        "Age verification for restricted purchases",
        "Loyalty programs linked to your BonID",
        "Secure in-store & online transactions",
        "Easy returns with verified purchase history"
      ]
    when "hospitality", "tourism"
      [
        "Express hotel check-in — no ID scanning",
        "Verified booking for tours & activities",
        "Seamless car rentals with digital ID",
        "VIP treatment at partner locations"
      ]
    when "real_estate"
      [
        "Faster tenant verification for rentals",
        "Streamlined property purchase documentation",
        "Digital signing for lease agreements",
        "Verified identity for property viewings"
      ]
    when "ngos", "community_organizations", "social_services", "disaster_relief"
      [
        "Quick beneficiary registration",
        "Transparent aid distribution tracking",
        "Verified volunteer & staff identity",
        "Secure donation & fund management"
      ]
    when "legal"
      [
        "Verified client identity for legal services",
        "Digital document signing with legal validity",
        "Streamlined notarization process",
        "Secure case file management"
      ]
    when "cryptocurrency"
      [
        "Compliant KYC for crypto exchanges",
        "Secure wallet recovery options",
        "Verified identity for large transactions",
        "Meet regulatory requirements easily"
      ]
    else
      [
        "Verified identity accepted across Haiti",
        "Skip repetitive document uploads",
        "Secure, tamper-proof digital ID",
        "Access services faster with BonID"
      ]
    end
  end
end
