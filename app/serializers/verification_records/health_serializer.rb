# frozen_string_literal: true

require "digest"

module VerificationRecords
  class HealthSerializer < ActiveModel::Serializer
    attributes :id,
               :record_type,
               :category,
               :patient_name,
               :patient_national_id,
               :patient_dob,
               :patient_gender,
               :provider_name,
               :policy_number,
               :coverage_type,
               :valid_from,
               :valid_until,
               :renewal_date,
               :premium_amount_htg,
               :coverage_limit_htg,
               :deductible_htg,
               :coinsurance_rate,
               :insured_name,
               :policy_holder_id,
               :blood_type,
               :doctor_name,
               :hospital_affiliation,
               :preferred_pharmacy,
               :last_checkup_date,
               :next_checkup_date,
               :verification_status,
               :verified_at,
               :partner_name,
               :data_checksum,
               :last_updated_at

    # ============================
    # === ATTRIBUTE HELPERS ===
    # ============================

    def patient_name
      object.data["patient_name"]
    end

    def patient_national_id
      object.data["patient_national_id"]
    end

    def patient_dob
      object.data["patient_dob"]
    end

    def patient_gender
      object.data["patient_gender"]
    end

    def provider_name
      object.data["provider_name"]
    end

    def policy_number
      object.data["policy_number"]
    end

    def coverage_type
      object.data["coverage_type"]
    end

    def valid_from
      object.data["valid_from"]
    end

    def valid_until
      object.data["valid_until"]
    end

    def renewal_date
      object.data["renewal_date"]
    end

    def premium_amount_htg
      object.data["premium_amount_htg"]
    end

    def coverage_limit_htg
      object.data["coverage_limit_htg"]
    end

    def deductible_htg
      object.data["deductible_htg"]
    end

    def coinsurance_rate
      object.data["coinsurance_rate"]
    end

    def insured_name
      object.data["insured_name"]
    end

    def policy_holder_id
      object.data["policy_holder_id"]
    end

    def blood_type
      object.data["blood_type"]
    end

    def doctor_name
      object.data["doctor_name"]
    end

    def hospital_affiliation
      object.data["hospital_affiliation"]
    end

    def preferred_pharmacy
      object.data["preferred_pharmacy"]
    end

    def last_checkup_date
      object.data["last_checkup_date"]
    end

    def next_checkup_date
      object.data["next_checkup_date"]
    end

    # === Verification Metadata ===
    def verification_status
      object.status
    end

    def verified_at
      object.verified_at&.iso8601
    end

    def partner_name
      object.partner&.name || object.verifier&.try(:name)
    end

    # === Integrity Hash ===
    def data_checksum
      payload = object.data.to_json
      Digest::SHA256.hexdigest(payload)[0..15]
    end

    def last_updated_at
      object.updated_at&.iso8601
    end
  end
end
