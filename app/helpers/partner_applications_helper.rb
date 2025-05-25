module PartnerApplicationsHelper
  
  DEPARTMENT_SECTORS = {
    "Public Sector" => [
      ["Government", :government],
      ["Border Control", :border_control],
      ["Law Enforcement", :law_enforcement],
      ["Local Governance", :local_governance],
      ["Electoral Systems", :electoral_systems],
      ["Public Health Campaigns", :public_health_campaigns],
      ["Public Transport", :public_transport],
      ["Sanitation", :sanitation],
      ["Utilities", :utilities]
    ],
    "Private Sector" => [
      ["Banking", :banking],
      ["Fintech", :fintech],
      ["Insurance", :insurance],
      ["Real Estate", :real_estate],
      ["Retail", :retail],
      ["Hospitality", :hospitality],
      ["Food and Beverage", :food_and_beverage],
      ["Media and Entertainment", :media_and_entertainment],
      ["Tourism", :tourism],
      ["Mining and Resources", :mining_and_resources]
    ],
    "NGO & Development" => [
      ["NGOs", :ngos],
      ["Disaster Relief", :disaster_relief],
      ["Environmental Conservation", :environmental_conservation],
      ["Community Organizations", :community_organizations],
      ["Social Services", :social_services]
    ],
    "Technology & Communication" => [
      ["Cryptocurrency", :cryptocurrency],
      ["Telecommunications", :telecommunications],
      ["Online Education", :online_education]
    ],
    "Education & Culture" => [
      ["Education", :education],
      ["Youth and Sports", :youth_and_sports],
      ["Event Management", :event_management],
      ["Art and Craft", :art_and_craft],
      ["Cultural Heritage", :cultural_heritage]
    ],
    "Legal & Embassy Services" => [
      ["Legal", :legal],
      ["Embassy Services", :embassy_services],
      ["Customs Service", :customs_service]
    ],
    "Health & Wellness" => [
      ["Healthcare", :healthcare],
      ["Adult Services", :adult_services],
      ["Human Resources", :human_resources]
    ],
    "Agriculture & Rural" => [
      ["Agriculture", :agriculture],
      ["Fisheries", :fisheries],
      ["Energy", :energy],
      ["Market Commerce", :market_commerce]
    ]
  }.freeze

  USE_CASES = {
    "Community and Culture" => [
      ["Community Leader Verification", "community_leader_verification"],
      ["Festival Volunteer Check-in", "festival_volunteer_checkin"],
      ["Religious Organization Membership", "religious_membership_kyc"],
      ["Sports Event Participant Verification", "sports_participant_verification"]
    ],
    "Education" => [
      ["Exam Candidate ID Validation", "exam_id_verification"],
      ["Library Membership Verification", "library_membership"],
      ["Online Course Enrollment", "e_learning_enrollment"],
      ["School Staff Identity Screening", "school_staff_screening"],
      ["Student Enrollment Verification", "student_enrollment"]
    ],
    "Financial Services" => [
      ["Bank Account Opening", "bank_account_opening"],
      ["Crypto Wallet KYC", "crypto_kyc"],
      ["Insurance Claim Verification", "insurance_claim_kyc"],
      ["Loan Application Identity Check", "loan_kyc"],
      ["Microfinance Borrower KYC", "microfinance_kyc"],
      ["Mobile Money KYC", "mobile_money_kyc"]
    ],
    "Government Services" => [
      ["Border Control Screening", "border_screening"],
      ["Court Case Identity Verification", "court_identity_check"],
      ["Embassy Services Verification", "embassy_verification"],
      ["Government Benefits Eligibility", "public_benefits_kyc"],
      ["Police ID Check in the Field", "field_authentication"],
      ["Public Transport Driver Licensing", "driver_licensing"],
      ["Voter Identity Validation", "voter_verification"]
    ],
    "Healthcare" => [
      ["Health Record Matching", "health_record_linking"],
      ["Patient Intake Verification", "patient_checkin"],
      ["Telemedicine Patient Verification", "telemedicine_verification"]
    ],
    "Legal and Property" => [
      ["E-Signature Verification", "signature_validation"],
      ["Land Ownership or Lease Match", "property_kyc"],
      ["Rental Agreement Identity Check", "rental_kyc"]
    ],
    "NGO and Aid" => [
      ["Charity Donation Recipient Verification", "charity_recipient_kyc"],
      ["Disaster Relief Identity Check", "disaster_relief_kyc"],
      ["NGO Aid Distribution Identity Check", "aid_kyc"]
    ],
    "Rural and Industry" => [
      ["Agricultural Subsidy Eligibility", "agriculture_subsidy_kyc"],
      ["Energy Cooperative KYC", "energy_coop_kyc"],
      ["Fisheries Subsidy Eligibility", "fisheries_subsidy_kyc"],
      ["Market Vendor Licensing", "market_vendor_licensing"],
      ["Waste Management Worker KYC", "waste_management_kyc"]
    ],
    "Telecom and Utilities" => [
      ["Phone Number to ID Linking", "telco_linkage"],
      ["SIM Registration", "sim_registration"],
      ["Water or Electricity Account KYC", "utilities_signup"]
    ],
    "Travel and Hospitality" => [
      ["Customs Clearance Identity Check", "customs_verification"],
      ["Hotel Guest Identity Check", "guest_checkin"],
      ["Ticketing + Event Check-in", "event_checkin"],
      ["Tourism Operator Licensing", "tourism_operator_licensing"],
      ["Transit Card Identity Match", "transit_pass_verification"]
    ],
    "Commercial and Other" => [
      ["Adult Content Age Verification", "age_verification_adult"],
      ["Job Applicant Identity Screening", "hr_screening"],
      ["Retail Loyalty Program Signup", "loyalty_signup"]
    ]
  }.freeze

  def self.department_sectors
    DEPARTMENT_SECTORS.map do |group, options|
      [group, options.sort_by { |label, _| label }]
    end
  end
  
  

  def self.use_cases_for_bonid
    USE_CASES.map { |group, items| [group, items.sort_by(&:first)] }
  end
  
end
