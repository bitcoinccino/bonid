# frozen_string_literal: true

require "bcrypt"

class TransactionConsent < ApplicationRecord
  belongs_to :citizen, class_name: "User"
  belongs_to :partner

  # ============================================================
  # CONSTANTS
  # ============================================================
  MAX_OTP_ATTEMPTS = 5

  TTL_BY_TYPE = {
    # ── Financial ──
    "account_opening"    => 15.minutes,
    "wire_transfer"      => 5.minutes,
    "p2p_transfer"       => 5.minutes,
    "remittance"         => 10.minutes,
    "bill_payment"       => 5.minutes,
    "merchant_payment"   => 5.minutes,
    "cash_out"           => 5.minutes,
    "cash_in"            => 5.minutes,
    "mobile_topup"       => 5.minutes,
    "loan_application"   => 15.minutes,
    # ── Identity & Compliance ──
    "kyc_check"          => 10.minutes,
    "balance_inquiry"    => 5.minutes,
    "age_verification"   => 10.minutes,
    # ── Documents & Services ──
    "card_issuance"      => 15.minutes,
    "insurance_claim"    => 15.minutes,
    "document_signing"   => 15.minutes,
    # ── Government (Haiti-specific) ──
    "civil_registry"     => 15.minutes,  # Archives Nationales — birth, marriage, death certificates
    "tax_service"        => 15.minutes,  # DGI — Matricule Fiscale, property taxes
    "identity_issuance"  => 15.minutes,  # ONI / Passport — CIN renewal, passport status
    "land_registry"      => 15.minutes,  # ONACA — property ownership verification
    "voter_status"       => 10.minutes,  # CEP — voter identity verification
    "judicial_record"    => 15.minutes,  # Tribunals — Casier Judiciaire (police record)
    # ── Crypto / Blockchain ──
    "crypto_buy"         => 5.minutes,   # Fiat-to-crypto on-ramp — high risk, full KYC + source of funds
    "crypto_sell"        => 5.minutes,   # Crypto-to-fiat off-ramp — AML reporting required
    "crypto_transfer"    => 10.minutes,  # Peer-to-peer on-chain — Travel Rule for transfers > $1000
    "crypto_swap"        => 10.minutes,  # Token-to-token exchange — no fiat, lower risk
    "crypto_kyc"         => 30.minutes,  # Exchange onboarding — enhanced due diligence (EDD)
    # ── Diplomacy / Embassies (US, CA, FR, BR) ──
    "consular_id"        => 15.minutes,  # Embassy — consular ID issuance / renewal
    "passport_renewal"   => 15.minutes,  # Embassy — passport renewal for diaspora
    "citizen_services"   => 15.minutes,  # Embassy — notarization, birth registration abroad
    "visa_processing"    => 15.minutes,  # Embassy — visa application identity check
    "diaspora_verify"    => 10.minutes,  # Embassy — verify Haitian identity for foreign services
    # ── Health & Biometric ──
    "medical_consultation"  => 15.minutes,  # Hospital/clinic — patient identity + health profile
    "pharmacy_check"        => 10.minutes,  # Pharmacy — medication & allergy verification
    "health_screening"      => 15.minutes,  # Lab — blood type, conditions, screening data
    "organ_donor_check"     => 10.minutes,  # Registry — organ donor status verification
    "blood_type_check"      => 10.minutes,  # Emergency — quick blood type lookup
    # ── Civil & Social ──
    "family_verification"      => 15.minutes,  # Family records — spouse, dependents, relationships
    "inheritance_check"        => 15.minutes,  # Notary — inheritance & succession verification
    "social_trust_score"       => 10.minutes,  # Social profile — trust score & endorsements
    "emergency_contact_lookup" => 5.minutes,   # Emergency services — contact persons
    "lending_kyc"              => 15.minutes   # Microfinance — civil records for lending decisions
  }.freeze

  DEFAULT_TTL = 10.minutes
  VALID_TRANSACTION_TYPES = TTL_BY_TYPE.keys.freeze

  # ============================================================
  # SECTOR-BASED TRANSACTION TYPE DEFAULTS
  # Admins can override per-partner; these are convenient defaults.
  # ============================================================
  DEFAULT_TRANSACTION_TYPES_BY_SECTOR = {
    "finance" => %w[
      account_opening wire_transfer p2p_transfer remittance
      bill_payment merchant_payment cash_out cash_in mobile_topup
      loan_application kyc_check balance_inquiry
    ],
    "government" => %w[
      civil_registry tax_service identity_issuance land_registry
      voter_status judicial_record document_signing
      age_verification kyc_check insurance_claim
    ],
    "law_enforcement" => %w[
      kyc_check age_verification judicial_record voter_status
    ],
    "cryptocurrency" => %w[
      crypto_buy crypto_sell crypto_transfer crypto_swap crypto_kyc
      kyc_check p2p_transfer balance_inquiry
    ],
    "diplomacy" => %w[
      consular_id passport_renewal citizen_services visa_processing
      diaspora_verify kyc_check identity_issuance
    ],
    "healthcare" => %w[
      medical_consultation pharmacy_check health_screening
      organ_donor_check blood_type_check insurance_claim
    ],
    "civil" => %w[
      civil_registry family_verification inheritance_check
      social_trust_score emergency_contact_lookup lending_kyc
    ],
    "default" => %w[
      p2p_transfer merchant_payment mobile_topup bill_payment
      cash_out cash_in balance_inquiry
    ]
  }.freeze

  FINANCE_SECTORS = %w[
    banking microfinance credit_union fintech insurance cryptocurrency
  ].freeze

  GOVERNMENT_SECTORS = %w[
    municipality ministry customs immigration
  ].freeze

  LAW_ENFORCEMENT_SECTORS = %w[pnh law_enforcement].freeze

  DIPLOMACY_SECTORS = %w[embassy consulate international_org embassy_services].freeze

  HEALTHCARE_SECTORS = %w[hospital clinic pharmacy laboratory health_ngo].freeze

  CIVIL_SECTORS = %w[notary ngo microfinance social_services community_org].freeze

  def self.default_types_for_sector(sector)
    s = sector.to_s.downcase
    if FINANCE_SECTORS.include?(s)
      DEFAULT_TRANSACTION_TYPES_BY_SECTOR["finance"]
    elsif GOVERNMENT_SECTORS.include?(s)
      DEFAULT_TRANSACTION_TYPES_BY_SECTOR["government"]
    elsif LAW_ENFORCEMENT_SECTORS.include?(s)
      DEFAULT_TRANSACTION_TYPES_BY_SECTOR["law_enforcement"]
    elsif DIPLOMACY_SECTORS.include?(s)
      DEFAULT_TRANSACTION_TYPES_BY_SECTOR["diplomacy"]
    elsif HEALTHCARE_SECTORS.include?(s)
      DEFAULT_TRANSACTION_TYPES_BY_SECTOR["healthcare"]
    elsif CIVIL_SECTORS.include?(s)
      DEFAULT_TRANSACTION_TYPES_BY_SECTOR["civil"]
    else
      DEFAULT_TRANSACTION_TYPES_BY_SECTOR["default"]
    end
  end

  # ============================================================
  # ENUMS
  # ============================================================
  enum :status, { pending: 0, approved: 1, denied: 2, expired: 3 }

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :consent_token, presence: true, uniqueness: true
  validates :transaction_type, presence: true, inclusion: { in: VALID_TRANSACTION_TYPES }
  validates :expires_at, presence: true
  validates :reference_id, uniqueness: { scope: [:citizen_id, :partner_id] },
            allow_blank: true

  # ============================================================
  # LIFECYCLE
  # ============================================================
  before_validation :generate_consent_token, on: :create
  before_validation :set_expiry, on: :create
  before_save :expire_if_due

  # ============================================================
  # SCOPES
  # ============================================================
  scope :active, -> { where(status: :pending).where("expires_at > ?", Time.current) }

  # ============================================================
  # OTP VERIFICATION
  # ============================================================
  def otp_valid?(code)
    return false if otp_digest.blank? || code.blank?
    return false if otp_attempts >= MAX_OTP_ATTEMPTS
    return false if otp_expired?

    BCrypt::Password.new(otp_digest).is_password?(code.to_s)
  end

  def otp_expired?
    otp_expires_at.present? && otp_expires_at < Time.current
  end

  def increment_otp_attempts!
    increment!(:otp_attempts)
  end

  def otp_locked?
    otp_attempts >= MAX_OTP_ATTEMPTS
  end

  # ============================================================
  # ACTIONS
  # ============================================================
  def approve!(ip:)
    update!(
      status: :approved,
      decided_at: Time.current,
      ip_address: ip
    )
    sign_consent!
    cache_for_data_access!
    append_audit!("approved", ip: ip)
  end

  def approve_with_biometric!(ip:, liveness_session_id:, confidence:, face_similarity: nil, compared_against: nil)
    attrs = {
      status: :approved,
      decided_at: Time.current,
      ip_address: ip,
      liveness_session_id: liveness_session_id,
      liveness_confidence: confidence,
      biometric_verified_at: Time.current
    }

    # Store face comparison result in metadata for audit trail
    if face_similarity
      current_meta = self.metadata || {}
      current_meta["face_comparison"] = {
        "similarity" => face_similarity,
        "threshold" => FaceMatchService::SIMILARITY_THRESHOLD,
        "compared_against" => compared_against,
        "compared_at" => Time.current.iso8601
      }
      attrs[:metadata] = current_meta
    end

    update!(attrs)
    sign_consent!
    cache_for_data_access!
    append_audit!("approved_biometric", ip: ip, liveness_session_id: liveness_session_id,
                  confidence: confidence.to_f, face_similarity: face_similarity&.to_f)
  end

  def deny!(ip:)
    update!(
      status: :denied,
      decided_at: Time.current,
      ip_address: ip
    )
    append_audit!("denied", ip: ip)
  end

  # ============================================================
  # HMAC SIGNATURE (non-repudiation proof)
  # ============================================================
  def sign_consent!
    proof = consent_proof
    sig = partner.sign_payload(proof)
    update_columns(signature: sig)
  end

  def consent_proof
    {
      consent_token: consent_token,
      bonid: citizen.bonid,
      partner_id: partner_id,
      transaction_type: transaction_type,
      reference_id: reference_id,
      amount: amount&.to_s,
      currency: currency,
      status: status,
      decided_at: decided_at&.iso8601,
      scopes: scopes
    }
  end

  # ============================================================
  # SUMMARY (for API responses)
  # ============================================================
  def summary
    {
      consent_token: consent_token,
      bonid: citizen.bonid,
      partner: partner.name,
      transaction_type: transaction_type,
      status: status,
      amount: amount&.to_s,
      currency: currency,
      reference_id: reference_id,
      signature: signature,
      decided_at: decided_at&.iso8601,
      expires_at: expires_at.iso8601,
      created_at: created_at.iso8601
    }
  end

  # ============================================================
  # AUDIT TRAIL
  # ============================================================
  def append_audit!(action, details = {})
    self.audit_log ||= {}
    self.audit_log[Time.current.iso8601] = {
      action: action,
      status: status,
      details: details,
      actor: Current.user&.id || "system"
    }
    save!(touch: false)
  end

  # ============================================================
  # TTL HELPER
  # ============================================================
  def ttl_for_type
    TTL_BY_TYPE[transaction_type] || DEFAULT_TTL
  end

  # ============================================================
  # DOUBLE-LOCK: DATA ACCESS CONTROL
  # ============================================================
  DEFAULT_DATA_ACCESS_WINDOW = 30.minutes

  # How long after approval the consent_token can pull identity data.
  # Configurable per-consent (set by partner plan or admin override).
  def data_access_window
    (data_access_window_minutes || 30).minutes
  end

  # Can this consent still be used to access identity data?
  def data_access_allowed?
    return false unless approved?
    return false if decided_at.blank?
    return false if decided_at + data_access_window < Time.current
    return false if burn_after_read? && data_access_count > 0
    true
  end

  # Record that identity data was accessed via this consent.
  # Called by background job (non-blocking).
  def record_data_access!(ip:, scopes_used:)
    increment!(:data_access_count)
    update_columns(data_accessed_at: Time.current)
    append_audit!("data_accessed", ip: ip, scopes: scopes_used, access_number: data_access_count)
  end

  # Burn the consent (one-time use for highest security).
  def burned?
    burn_after_read? && data_access_count > 0
  end

  # Cache consent validation in Redis for fast lookups.
  # Called after approval — stores scopes + expiry for ~30min.
  def cache_for_data_access!
    return unless approved? && decided_at.present?

    cache_key = "consent:#{consent_token}:#{partner_id}"
    cache_data = {
      citizen_bonid: citizen.bonid,
      scopes: scopes,
      burn_after_read: burn_after_read?,
      data_access_count: data_access_count,
      expires_at: (decided_at + data_access_window).iso8601
    }
    Rails.cache.write(cache_key, cache_data, expires_in: data_access_window)
  end

  # Read cached consent data from Redis (returns nil on miss).
  def self.cached_consent(consent_token, partner_id)
    Rails.cache.read("consent:#{consent_token}:#{partner_id}")
  end

  # Invalidate cache (called after data access on burn_after_read).
  def invalidate_cache!
    Rails.cache.delete("consent:#{consent_token}:#{partner_id}")
  end

  private

  def generate_consent_token
    self.consent_token ||= SecureRandom.hex(16)
  end

  def set_expiry
    self.expires_at ||= ttl_for_type.from_now
    self.otp_expires_at ||= self.expires_at
  end

  def expire_if_due
    self.status = :expired if pending? && expires_at.present? && expires_at < Time.current
  end
end
