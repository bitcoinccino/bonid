class PartnerApplication < ApplicationRecord
  has_one :address, as: :addressable, dependent: :destroy
  accepts_nested_attributes_for :address
  has_one_attached :logo
  belongs_to :partner, optional: true
  has_one :partner
  before_save :remove_blank_use_cases

  validates :organization_name, :contact_person, :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

   #  Validations for law enforcement
   with_options if: :law_enforcement_sector? do
    validates :unit_name, presence: true
    validates :unit_type, presence: true
  end

  def law_enforcement_sector?
    department_sector == "law_enforcement"
  end

  

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

  REJECTION_REASONS = [
    "Missing required information",
    "Invalid or unverifiable address",
    "Organization does not meet criteria",
    "Unsupported sector or use case",
    "Unable to verify legitimacy",
    "Duplicate or fraudulent submission",
    "Unresponsive contact person",
    "Document or logo issues",
    "Currently not accepting new partners",
    "Other"
  ].freeze


  def self.use_cases_for_bonid
    USE_CASES.map { |group, items| [group, items.sort_by(&:first)] }
  end

  DEPARTMENT_SECTORS = {
    "Commerce" => [
      ["Art and Craft", :art_and_craft],
      ["Food and Beverage", :food_and_beverage],
      ["Hospitality", :hospitality],
      ["Market Commerce", :market_commerce],
      ["Retail", :retail],
      ["Tourism", :tourism]
    ],
    "Financial Services" => [
      ["Banking", :banking],
      ["Cryptocurrency", :cryptocurrency],
      ["Fintech", :fintech],
      ["Insurance", :insurance]
    ],
    "Public Services" => [
      ["Border Control", :border_control],
      ["Customs Service", :customs_service],
      ["Electoral Systems", :electoral_systems],
      ["Embassy Services", :embassy_services],
      ["Government", :government],
      ["Law Enforcement", :law_enforcement],
      ["Local Governance", :local_governance]
    ],
    "Social Impact" => [
      ["Community Organizations", :community_organizations],
      ["Cultural Heritage", :cultural_heritage],
      ["Disaster Relief", :disaster_relief],
      ["NGOs", :ngos],
      ["Public Health Campaigns", :public_health_campaigns],
      ["Social Services", :social_services]
    ],
    "Education and Media" => [
      ["Education", :education],
      ["Media and Entertainment", :media_and_entertainment],
      ["Online Education", :online_education],
      ["Youth and Sports", :youth_and_sports]
    ],
    "Healthcare" => [
      ["Healthcare", :healthcare]
    ],
    "Industry and Environment" => [
      ["Agriculture", :agriculture],
      ["Energy", :energy],
      ["Environmental Conservation", :environmental_conservation],
      ["Fisheries", :fisheries],
      ["Mining and Resources", :mining_and_resources],
      ["Sanitation", :sanitation]
    ],
    "Services and Infrastructure" => [
      ["Human Resources", :human_resources],
      ["Legal", :legal],
      ["Public Transport", :public_transport],
      ["Real Estate", :real_estate],
      ["Telecommunications", :telecommunications],
      ["Utilities", :utilities],
      ["Adult Services", :adult_services]
    ]
  }.freeze

  def self.department_sectors
    DEPARTMENT_SECTORS.map do |group, options|
      [group, options.sort_by { |label, _| label }]
    end
  end

  private

  def remove_blank_use_cases
    self.use_cases = use_cases.reject(&:blank?) if use_cases.is_a?(Array)
  end
end

