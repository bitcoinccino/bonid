# frozen_string_literal: true

require "digest"

module VerificationRecords
  class BusinessSerializer < ActiveModel::Serializer
    attributes :id,
               :record_type,
               :category,
               :business_name,
               :registration_number,
               :legal_structure,
               :nif,
               :business_address,
               :sector,
               :cnss_employer_number,
               :incorporation_date,
               :license_expiration_date,
               :verification_status,
               :verified_at,
               :verifier_signature,
               :partner_name,
               :data_checksum,
               :last_updated_at

    # ============================
    # === ATTRIBUTE HELPERS ===
    # ============================

    def business_name
      object.data["business_name"]
    end

    def registration_number
      object.data["registration_number"]
    end

    def legal_structure
      object.data["legal_structure"]
    end

    def nif
      object.data["nif"]
    end

    def business_address
      object.data["business_address"]
    end

    def sector
      object.data["sector"]
    end

    def cnss_employer_number
      object.data["cnss_employer_number"]
    end

    def incorporation_date
      object.data["incorporation_date"]
    end

    def license_expiration_date
      object.data["license_expiration_date"]
    end

    # === Business Record Status ===
    def verification_status
      object.status
    end

    def verified_at
      object.verified_at&.iso8601
    end

    def verifier_signature
      object.verifier_signature
    end

    # === Linked Partner (verifier) ===
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
