# db/seeds/crime_types.rb
# Seed crime categories and types from existing IncidentReport::CRIME_TYPES

puts "Seeding crime categories and types..."

# Define categories with metadata
CATEGORIES = {
  violent: {
    name: "Violent Crimes",
    code: "VIOLENT",
    description: "Crimes involving physical harm or threat of harm",
    display_order: 1
  },
  property: {
    name: "Property Crimes",
    code: "PROPERTY",
    description: "Crimes involving theft or damage to property",
    display_order: 2
  },
  financial: {
    name: "Financial Crimes",
    code: "FINANCIAL",
    description: "Economic and white-collar crimes",
    display_order: 3
  },
  public_order: {
    name: "Public Order",
    code: "PUBLIC",
    description: "Crimes against public peace and order",
    display_order: 4
  },
  traffic: {
    name: "Traffic Offenses",
    code: "TRAFFIC",
    description: "Vehicle and road-related offenses",
    display_order: 5
  },
  organized: {
    name: "Organized Crime",
    code: "ORGANIZED",
    description: "Gang and organized criminal activity",
    display_order: 6
  },
  other: {
    name: "Other",
    code: "OTHER",
    description: "Miscellaneous offenses",
    display_order: 7
  }
}.freeze

# Crime types with their attributes
# Format: [name, code, category_key, base_severity, description]
CRIME_TYPES_DATA = [
  # Violent Crimes
  ["Homicide", "HOM", :violent, 5, "Unlawful killing of a person"],
  ["Attempted Homicide", "ATH", :violent, 5, "Attempted unlawful killing"],
  ["Assault", "AST", :violent, 3, "Physical attack on a person"],
  ["Aggravated Assault", "AGG", :violent, 4, "Assault with weapon or severe injury"],
  ["Battery", "BAT", :violent, 3, "Unlawful physical contact"],
  ["Robbery", "ROB", :violent, 4, "Theft using force or threat"],
  ["Armed Robbery", "ARB", :violent, 5, "Robbery with a weapon"],
  ["Kidnapping", "KID", :violent, 5, "Unlawful abduction of a person"],
  ["Sexual Assault", "SEX", :violent, 5, "Non-consensual sexual contact"],
  ["Rape", "RAP", :violent, 5, "Forcible sexual intercourse"],
  ["Domestic Violence", "DOM", :violent, 4, "Violence within domestic relationships"],
  ["Child Abuse", "CHA", :violent, 5, "Physical or emotional harm to children"],
  ["Elder Abuse", "ELA", :violent, 4, "Abuse of elderly persons"],

  # Property Crimes
  ["Theft", "THF", :property, 2, "Unlawful taking of property"],
  ["Grand Theft", "GTH", :property, 3, "Theft of high-value property"],
  ["Petty Theft", "PTH", :property, 1, "Theft of low-value items"],
  ["Burglary", "BUR", :property, 3, "Unlawful entry with intent to commit crime"],
  ["Home Invasion", "HIN", :property, 4, "Burglary of occupied dwelling"],
  ["Vehicle Theft", "VTH", :property, 3, "Stealing a motor vehicle"],
  ["Carjacking", "CAR", :property, 4, "Vehicle theft using force or threat"],
  ["Vandalism", "VAN", :property, 2, "Destruction of property"],
  ["Arson", "ARS", :property, 4, "Intentionally setting fire to property"],
  ["Trespassing", "TRS", :property, 1, "Unlawful entry onto property"],

  # Financial Crimes
  ["Fraud", "FRD", :financial, 3, "Deception for financial gain"],
  ["Identity Theft", "IDT", :financial, 3, "Using another's identity for fraud"],
  ["Forgery", "FOR", :financial, 3, "Creating false documents"],
  ["Embezzlement", "EMB", :financial, 3, "Misappropriation of entrusted funds"],
  ["Extortion", "EXT", :financial, 4, "Obtaining something through threats"],
  ["Bribery", "BRI", :financial, 3, "Offering or accepting corrupt payments"],
  ["Money Laundering", "MLN", :financial, 4, "Concealing illicit money sources"],
  ["Counterfeiting", "CTF", :financial, 3, "Creating fake currency or goods"],
  ["Tax Evasion", "TAX", :financial, 3, "Illegally avoiding taxes"],

  # Public Order
  ["Disorderly Conduct", "DIS", :public_order, 1, "Disturbing the peace"],
  ["Public Intoxication", "INT", :public_order, 1, "Being drunk in public"],
  ["Illegal Assembly", "ILA", :public_order, 2, "Unlawful gathering"],
  ["Rioting", "RIO", :public_order, 3, "Violent public disturbance"],
  ["Looting", "LOO", :public_order, 3, "Theft during civil unrest"],
  ["Prostitution", "PRO", :public_order, 2, "Engaging in commercial sex"],
  ["Gambling", "GAM", :public_order, 1, "Illegal gambling activities"],
  ["Weapons Violation", "WPN", :public_order, 3, "Illegal possession or use of weapons"],
  ["Drug Possession", "DPO", :public_order, 2, "Illegal drug possession"],
  ["Drug Trafficking", "DTR", :public_order, 4, "Drug distribution and sales"],

  # Traffic Offenses
  ["Reckless Driving", "RKD", :traffic, 2, "Dangerous vehicle operation"],
  ["DUI/DWI", "DUI", :traffic, 3, "Driving under the influence"],
  ["Hit and Run", "HAR", :traffic, 3, "Leaving accident scene"],
  ["Vehicular Manslaughter", "VMS", :traffic, 5, "Death caused by vehicle operation"],
  ["Driving Without License", "DWL", :traffic, 1, "Operating vehicle without valid license"],
  ["Speeding", "SPD", :traffic, 1, "Exceeding speed limits"],

  # Organized Crime
  ["Gang Activity", "GNG", :organized, 4, "Criminal gang involvement"],
  ["Human Trafficking", "HTR", :organized, 5, "Trading in human beings"],
  ["Smuggling", "SMG", :organized, 4, "Illegal transport of goods or persons"],
  ["Racketeering", "RKT", :organized, 4, "Organized criminal enterprise"],

  # Other
  ["Obstruction of Justice", "OBJ", :other, 3, "Interfering with legal proceedings"],
  ["Perjury", "PER", :other, 3, "Lying under oath"],
  ["Resisting Arrest", "RES", :other, 2, "Opposing lawful arrest"],
  ["Escape", "ESC", :other, 3, "Fleeing lawful custody"],
  ["Harassment", "HRS", :other, 2, "Persistent unwanted behavior"],
  ["Stalking", "STK", :other, 3, "Repeatedly following or threatening"],
  ["Cybercrime", "CYB", :other, 3, "Computer-related crimes"],
  ["Other", "OTH", :other, 2, "Miscellaneous offenses"]
].freeze

# Severity rules for context-based adjustments
SEVERITY_RULES = [
  { crime_codes: %w[AST BAT ROB THF BUR], condition_type: "weapon_involved", modifier: 2 },
  { crime_codes: %w[AST BAT DOM], condition_type: "minor_victim", modifier: 1 },
  { crime_codes: %w[ROB THF BUR], condition_type: "multiple_perpetrators", modifier: 1 },
  { crime_codes: %w[AST ROB DOM], condition_type: "repeat_offender", modifier: 1 },
  { crime_codes: %w[VAN THF DIS], condition_type: "gang_related", modifier: 2 }
].freeze

# Related crime types (often occur together or escalate)
RELATED_CRIMES = [
  { from: "THF", to: "ROB", relationship: "escalation", correlation: 0.7 },
  { from: "AST", to: "AGG", relationship: "escalation", correlation: 0.8 },
  { from: "DOM", to: "HOM", relationship: "escalation", correlation: 0.5 },
  { from: "BUR", to: "THF", relationship: "often_together", correlation: 0.9 },
  { from: "DPO", to: "DTR", relationship: "escalation", correlation: 0.6 },
  { from: "GNG", to: "DTR", relationship: "often_together", correlation: 0.8 },
  { from: "GNG", to: "ARB", relationship: "often_together", correlation: 0.7 },
  { from: "RIO", to: "LOO", relationship: "often_together", correlation: 0.85 },
  { from: "DUI", to: "HAR", relationship: "often_together", correlation: 0.6 },
  { from: "DUI", to: "VMS", relationship: "escalation", correlation: 0.4 }
].freeze

# Create categories
categories = {}
CATEGORIES.each do |key, attrs|
  category = CrimeCategory.find_or_create_by!(code: attrs[:code]) do |c|
    c.name = attrs[:name]
    c.description = attrs[:description]
    c.display_order = attrs[:display_order]
    c.active = true
  end
  categories[key] = category
  puts "  Created category: #{category.name}"
end

# Create crime types
crime_types = {}
CRIME_TYPES_DATA.each do |name, code, category_key, severity, description|
  category = categories[category_key]
  crime_type = CrimeType.find_or_create_by!(code: code) do |ct|
    ct.name = name
    ct.crime_category = category
    ct.base_severity = severity
    ct.description = description
    ct.active = true
  end
  crime_types[code] = crime_type
end
puts "  Created #{crime_types.count} crime types"

# Create severity rules
SEVERITY_RULES.each do |rule|
  rule[:crime_codes].each do |code|
    crime_type = crime_types[code]
    next unless crime_type

    SeverityRule.find_or_create_by!(
      crime_type: crime_type,
      condition_type: rule[:condition_type]
    ) do |sr|
      sr.severity_modifier = rule[:modifier]
      sr.description = "#{rule[:condition_type].titleize} increases severity"
    end
  end
end
puts "  Created severity rules"

# Create related crime types
RELATED_CRIMES.each do |rel|
  from_type = crime_types[rel[:from]]
  to_type = crime_types[rel[:to]]
  next unless from_type && to_type

  RelatedCrimeType.find_or_create_by!(
    crime_type: from_type,
    related_crime_type: to_type
  ) do |rct|
    rct.relationship_type = rel[:relationship]
    rct.correlation_score = rel[:correlation]
  end
end
puts "  Created related crime type mappings"

puts "Crime classification seeding complete!"
