# app/models/concerns/ticket_constants.rb
module TicketConstants
  extend ActiveSupport::Concern

  # Severity levels: 1 (Minor) to 5 (Severe/Criminal)
  TICKET_SEVERITY = {
    "speeding" => 2,
    "red_light_violation" => 2,
    "stop_sign_violation" => 2,
    "no_license" => 3,
    "no_registration" => 3,
    "no_insurance" => 3,
    "no_puc" => 2,
    "faulty_equipment" => 2,
    "driving_under_influence" => 5, # Upgraded to Severe
    "mobile_phone_use" => 2,
    "overloading" => 3,
    "no_helmet" => 2,
    "illegal_parking" => 1,
    "public_disturbance" => 2,
    "petty_theft" => 3,
    "vandalism" => 3,
    "notice_challan" => 2,
    "court_challan" => 5, # Directly to Parquet
    "no_car_inspection" => 2,
    "carrying_animals_with_people" => 2,
    "selling_without_permit" => 2,
    "building_without_permit" => 3,
    "littering" => 1,
    "school_zone_violation" => 3,
    "reckless_driving" => 4,
    "blocking_roadway" => 2,
    "noise_violation" => 2,
    "unpermitted_public_gathering" => 3,
    "improper_waste_disposal" => 2,
    "expired_license" => 3
  }.freeze

  # Mnemonic Codes for PNH/DCPR Database
  TICKET_CODES = {
    "speeding" => "SPEED",
    "red_light_violation" => "LIGHT",
    "stop_sign_violation" => "SIGN",
    "no_license" => "DRIV",
    "no_registration" => "VEHI",
    "no_insurance" => "INSUR",
    "no_puc" => "NOP", # Pollution Check
    "faulty_equipment" => "LIGHTS",
    "driving_under_influence" => "INTO",
    "mobile_phone_use" => "PHONE",
    "overloading" => "OVL",
    "no_helmet" => "NHM",
    "illegal_parking" => "PARK",
    "public_disturbance" => "PUBD",
    "petty_theft" => "PETT",
    "vandalism" => "VAND",
    "notice_challan" => "NCH",
    "court_challan" => "CCH",
    "no_car_inspection" => "OAVCT", # Integrated with OAVCT
    "carrying_animals_with_people" => "CAP",
    "selling_without_permit" => "SWP",
    "building_without_permit" => "BWP",
    "littering" => "LITT",
    "school_zone_violation" => "SZV",
    "reckless_driving" => "RCK",
    "blocking_roadway" => "OBST",
    "noise_violation" => "NSV",
    "unpermitted_public_gathering" => "UPG",
    "improper_waste_disposal" => "IWD",
    "expired_license" => "EXL"
  }.freeze

  # Haitian Gourde (HTG) Fine Schedule
  TICKET_FINES = {
    "SPEED" => 2000, "LIGHT" => 1500, "SIGN"  => 1000, "DRIV"  => 2500,
    "VEHI"  => 1500, "INSUR" => 3000, "INTO"  => 5000, "PHONE" => 1000,
    "PARK"  => 250,  "OBST"  => 2000, "LITT"  => 500,  "OAVCT" => 2500,
    "RCK"   => 3500, "UPG"   => 2000, "VAND"  => 3000, "PETT"  => 1500
  }.freeze

  TICKET_STATUS = {
    open: 0,      # Ouvert
    paid: 1,      # Payé (via MonCash)
    cancelled: 2, # Annulé (Admin only)
    disputed: 3   # Contesté (At Parquet)
  }.freeze

  TICKET_TYPES = TICKET_SEVERITY.keys.freeze
end
