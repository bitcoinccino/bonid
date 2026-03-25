# frozen_string_literal: true

module PartnerUseCases
  extend ActiveSupport::Concern

  # ======================================
  # 1. Dynamic Use Cases Per Sector
  # ======================================
  USE_CASES = {
    "pnh" => [
      "Roadside ID verification",
      "Vehicle stop identity check",
      "Detainee verification",
      "Criminal record lookup",
      "Warrant check",
      "Incident report linking",
      "Cross-unit checks (CIMO / DCPJ / BLTS / UDMO / SWAT)",
      "Border checkpoint verification",
      "Missing person / BOLO match",
      "Officer authentication",
      "Internal personnel verification",
      "Victim/witness identity check",
      "Complaint intake",
      "Election day identity verification",
      "Polling station security checks",
      "Other"
    ],

    # BANKING
    "banking" => [
      "Customer Onboarding (KYC)",
      "Loan Application Verification",
      "Account Opening",
      "Fraud Prevention",
      "Compliance & AML Screening",
      "High-value transaction checks",
      "Other"
    ],

    # HOSPITALS
    "hospital" => [
      "Patient intake",
      "Medical record matching",
      "Emergency contact verification",
      "Health insurance validation",
      "Lab result verification",
      "Other"
    ],

    # EDUCATION
    "education" => [
      "Student enrollment",
      "Exam ID validation",
      "Staff background verification",
      "Parent/guardian identity checks",
      "Scholarship verification",
      "Other"
    ],

    # EMBASSY / CONSULATE
    "embassy_services" => [
      "Visa application identity checks",
      "Passport renewal",
      "Consular services",
      "Travel document validation",
      "Other"
    ],

    # FINTECH
    "fintech" => [
      "KYC",
      "Fraud prevention",
      "Customer verification",
      "Claims validation",
      "API Integrations",
      "Other"
    ],

    # INSURANCE
    "insurance" => [
      "Claims Verification",
      "Customer identity checks",
      "Payout verification",
      "Internal staff validation",
      "API Integrations",
      "Other"
    ],

    # RETAIL
    "retail" => [
      "Employee Verification",
      "Customer KYC",
      "Visitor Registration",
      "High-value purchase verification",
      "API Integrations",
      "Other"
    ],

    # FALLBACK
    "default" => [
      "Identity Verification",
      "Registration / Onboarding",
      "Fraud Prevention",
      "Compliance",
      "User Authentication",
      "Other"
    ]
  }.freeze

  # ======================================
  # 2. Integration Options
  # ======================================
  INTEGRATION_OPTIONS = [
    [ "Web Portal only (no coding)", "portal_only" ],
    [ "API Integration (developer available)", "api" ],
    [ "Both Portal + API", "both" ],
    [ "Not sure yet", "unsure" ]
  ].freeze

  # ======================================
  # 3. Discovery Options
  # ======================================
  DISCOVERY_OPTIONS = [
    [ "Referral", "referral" ],
    [ "Government / BRH", "government" ],
    [ "Social Media", "social_media" ],
    [ "Conference / Event", "event" ],
    [ "Embassy", "embassy" ],
    [ "Online Search", "search" ],
    [ "Other", "other" ]
  ].freeze

  # Helper method with fallback
  def self.for_sector(sector)
    USE_CASES[sector] || USE_CASES["default"]
  end
end
