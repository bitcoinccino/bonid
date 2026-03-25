# frozen_string_literal: true

class VerificationRecord < ApplicationRecord
  # ============================================================
  # Schemas / concerns
  # ============================================================
  include RecordSchemas::PropertySchema
  include RecordSchemas::LandTransactionSchema
  include RecordSchemas::BusinessSchema
  include RecordSchemas::FiscalReceiptSchema

  # ============================================================
  # Associations
  # ============================================================
  belongs_to :user
  belongs_to :verifier, polymorphic: true, optional: true
  belongs_to :partner, optional: true
  belongs_to :partner_schema, optional: true

  has_one :address, as: :addressable, dependent: :destroy

  accepts_nested_attributes_for :address, update_only: true, allow_destroy: true

  # ============================================================
  # Scopes
  # ============================================================
  scope :by_partner, ->(partner) { where(partner_id: partner.id) }
  scope :for_type_and_category, ->(type, cat) { where(record_type: type, category: cat) }
  scope :for_type, ->(t) { where(record_type: t) }
  scope :active, -> { where.not(status: "revoked") }

  # ============================================================
  # Enums
  # ============================================================
  enum :access_level, { private_access: 0, partners_access: 1, public_access: 2 }

  # ============================================================
  # Validations
  # ============================================================
  validates :record_type, presence: true
  validates :data, presence: true
  validates :status, inclusion: { in: %w[pending verified rejected revoked] }

  validate :validate_against_partner_schema, if: -> { partner_schema.present? && data.is_a?(Hash) }
  validate :property_schema, if: -> { record_type == "property" && partner.blank? }

  # ============================================================
  # JSONB Accessors (⚠️ NO NAME COLLISIONS)
  # ============================================================
  store_accessor :data,
    # --- Property ---
    :title_number,
    :cadastral_ref,
    :commune,
    :section_communal,
    :property_address,      # ✅ renamed (NOT `address`)
    :area_m2,
    :property_type,
    :zoning_use,
    :owner_since,
    :coowners,
    :permit,
    :valuation,
    :documents,
    :legal,
    :coordinates,

    # --- Business ---
    :business_name,
    :trade_name,
    :registration_number,
    :registration_authority,
    :business_type,
    :legal_structure,
    :nif,
    :cnss_employer_number,
    :tax_status,
    :vat_registered,
    :owner_role_custom,
    :business_address,
    :sector,
    :subsector,
    :employees_count,
    :average_monthly_salary_htg,
    :annual_revenue_htg,
    :license_expiration_date,
    :incorporation_date,
    :verified_by_partner,
    :verification_date,
    :risk_rating,
    :compliance_status,
    :compliance_notes,

    # --- Common ---
    :owner_name,
    :owner_bonid,
    :contact_email,
    :contact_phone,
    :website,
    :iban_or_bank_account,
    :geo_coordinates

  # ============================================================
  # Callbacks
  # ============================================================
  before_save :normalize_json_keys
  before_save :encrypt_sensitive_fields
  after_find  :decrypt_runtime

  # ============================================================
  # Property Validation (Citizen flow)
  # ============================================================
  def property_schema
    missing = []
    missing << "title_number"      if title_number.blank?
    missing << "property_address"  if property_address.blank?
    missing << "commune"           if commune.blank?

    errors.add(:data, "missing required fields: #{missing.join(', ')}") if missing.any?
  end

  # ============================================================
  # Partner Schema Validation
  # ============================================================
  def validate_against_partner_schema
    schema = PartnerSchema.active.find_by(partner: partner, record_type: record_type)
    return errors.add(:base, "No active schema found for #{partner.name} (#{record_type})") unless schema

    schemer = JSONSchemer.schema(schema.structure.deep_symbolize_keys)

    return if schemer.valid?(data)

    errors.add(:base, "Record data does not match the #{schema.name} definition")

    schemer.validate(data).each do |error|
      field = error[:data_pointer].presence || "root"
      errors.add(:data, "#{field}: #{error[:message]}")
    end
  rescue => e
    errors.add(:base, "Schema validation failed: #{e.message}")
  end

  # ============================================================
  # Helpers
  # ============================================================
  def full_address
    [ property_address, commune, "Haiti" ].compact.join(", ")
  end

  def coowners_list
    Array(coowners).map { |c| c["name"] }.compact.join(", ")
  end

  def market_value
    valuation.is_a?(Hash) ? valuation["market_value_htg"].to_i : nil
  end

  def permit_number
    permit.is_a?(Hash) ? permit["number"] : nil
  end

  def boundary_confirmed?
    legal.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(legal["boundary_confirmed"])
  end

  def verified?
    status == "verified"
  end

  def summary
    base =
      title_number ||
      business_name ||
      (record_type == "fiscal_receipt" ? receipt_summary : nil) ||
      owner_name ||
      property_address

    [ record_type.to_s.titleize, base ].compact.join(": ")
  end

  # ============================================================
  # Cryptographic Signatures
  # ============================================================
  def sign!(secret:)
    self.verifier_signature = OpenSSL::HMAC.hexdigest("SHA256", secret, canonical_payload)
    self.verified_at = Time.current
    self.status = "verified"
    save!
  end

  def valid_signature?(secret:)
    return false if verifier_signature.blank?

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, canonical_payload)
    ActiveSupport::SecurityUtils.secure_compare(expected, verifier_signature)
  end

  # ============================================================
  # Internal Helpers
  # ============================================================
  private

  def normalize_json_keys
    self.data     = data.deep_transform_keys(&:downcase)     if data.is_a?(Hash)
    self.metadata = metadata.deep_transform_keys(&:downcase) if metadata.is_a?(Hash)
  end

  def encrypt_sensitive_fields
    return unless data.is_a?(Hash)

    key = ActiveSupport::KeyGenerator
            .new(Rails.application.credentials.secret_key_base)
            .generate_key("verification-records", 32)

    encryptor = ActiveSupport::MessageEncryptor.new(key)

    %w[id_number passport_number national_id salary tax_id nif business_address].each do |field|
      next unless data[field].present?
      next if data[field].start_with?("--")

      data[field] = encryptor.encrypt_and_sign(data[field])
    end
  end

  def decrypt_sensitive_fields
    return data unless data.is_a?(Hash)

    key = ActiveSupport::KeyGenerator
            .new(Rails.application.credentials.secret_key_base)
            .generate_key("verification-records", 32)

    encryptor = ActiveSupport::MessageEncryptor.new(key)

    decrypted = data.deep_dup

    %w[id_number passport_number national_id salary tax_id nif business_address].each do |field|
      next unless decrypted[field].present?

      decrypted[field] =
        encryptor.decrypt_and_verify(decrypted[field])
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      decrypted[field]
    end

    decrypted
  end

  def decrypt_runtime
    self.data = decrypt_sensitive_fields
  end

  def canonical_payload
    Oj.dump(
      {
        user_id: user_id,
        record_type: record_type,
        category: category,
        data: data,
        verified_at: verified_at&.iso8601
      },
      mode: :strict
    )
  end
end
