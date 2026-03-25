# config/initializers/consent_scopes.rb
# frozen_string_literal: true

CONSENT_SCOPES = {
  identity: {
    label: "Identity Information",
    description: "Verified personal information including name, date of birth, sex, nationality, BonID number, and official ID images.",
    models: {
      "User" => %w[
        first_name
        last_name
        dob
        sex
        nationality
        bonid
        email
        phone_number
      ],
      "IdentitySubmission" => %w[
        id_type
        submission_type
        status
        approved_at
        rejected_at
        reason
        selfie_url
        cin_front_url
        cin_back_url
        passport_url
        proof_of_address_url
        qr_png_base64
      ],
      "Address" => %w[
        department_name
        arrondissement_name
        commune_name
        postal_code
        street_address
        latitude
        longitude
      ]
    }
  },

  bank: {
    label: "Banking & Financial Profile",
    description: "Verified KYC and financial linkage information for regulated institutions.",
    models: {
      "BankProfile" => %w[
        bank_name
        branch_name
        account_number
        kyc_verified
        kyc_verified_at
        wallet_address
        wallet_provider
        last_transaction_at
        risk_score
      ],
      "User" => %w[
        first_name
        last_name
        bonid
        email
        phone_number
      ]
    }
  },

  health: {
    label: "Health Profile",
    description: "Blood type, allergies, medical conditions, and health screening data.",
    models: {
      "HealthProfile" => %w[
        blood_type
        allergies
        chronic_conditions
        medications
        disabilities
        organ_donor
        insurance_provider
        insurance_number
      ],
      "User" => %w[
        first_name
        last_name
        bonid
        dob
        sex
      ]
    }
  },

  physical: {
    label: "Physical Profile",
    description: "Height, weight, eye color, hair, body type, skin tone, and distinguishing features.",
    models: {
      "PhysicalProfile" => %w[
        height_cm
        weight_kg
        eye_color
        hair_color
        hair_style
        body_type
        skin_tone
        race
        facial_hair
        handedness
      ],
      "User" => %w[
        first_name
        last_name
        bonid
        sex
      ]
    }
  },

  civil: {
    label: "Civil & Family Records",
    description: "Family members, place of birth, guardian relationships, and civil registry data.",
    models: {
      "FamilyMember" => %w[
        relationship
        guardian_type
        first_name
        last_name
        date_of_birth
        place_of_birth
        nationality
        alive
        verification_status
      ],
      "User" => %w[
        first_name
        last_name
        bonid
        dob
        nationality
        place_of_birth
      ]
    }
  },

  social: {
    label: "Social Handles & Trust",
    description: "Social media profiles, verification status, and trust weight scores.",
    models: {
      "SocialHandle" => %w[
        platform
        handle
        verification_status
        trust_weight
      ],
      "User" => %w[
        first_name
        last_name
        bonid
      ]
    }
  },

  emergency_contacts: {
    label: "Emergency Contacts",
    description: "Emergency contact persons with names, phone numbers, and relationships.",
    models: {
      "EmergencyContact" => %w[
        full_name
        phone
        relation
        verification_status
      ],
      "User" => %w[
        first_name
        last_name
        bonid
      ]
    }
  }
}.freeze
