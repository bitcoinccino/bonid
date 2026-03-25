class Citizen < User
  devise :registerable, :trackable  # Enable self-registration & login tracking for citizens

  # === Associations ===
  has_many :bank_profiles,
           class_name: "BankProfile",
           dependent: :destroy,
           foreign_key: :user_id,
           inverse_of: :user

  alias_method :financial_profiles, :bank_profiles

  accepts_nested_attributes_for :bank_profiles,
                                allow_destroy: true,
                                reject_if: ->(attrs) {
                                  # Reject if no meaningful data based on account type:
                                  # - Banks need bank_name
                                  # - Mobile/Crypto wallets need wallet_provider
                                  # Note: Rails params use string keys, not symbols
                                  bank_name = attrs["bank_name"] || attrs[:bank_name]
                                  wallet_provider = attrs["wallet_provider"] || attrs[:wallet_provider]
                                  should_reject = bank_name.blank? && wallet_provider.blank?
                                  Rails.logger.info "📊 [Citizen] reject_if check: bank_name=#{bank_name.inspect}, wallet_provider=#{wallet_provider.inspect}, reject=#{should_reject}"
                                  should_reject
                                }

  # === Validations ===
  with_options on: :citizen_profile_update do
    validates :first_name, :last_name, :dob, :sex, :phone, presence: true
    validates :id_type, :id_number, presence: true
    validates_associated :address
  end

  validate :citizen_role_required, on: :create

  # === Callbacks ===
  after_create :ensure_citizen_role

  # === OTP Validation ===
  def otp_valid?
    otp_sent_at.present? && otp_sent_at > 10.minutes.ago
  end

  # === Override for Citizen Context ===
  def bonid_profile
    super.merge(
      role: "citizen",
      financial_accounts: financial_profiles.pluck(:bank_name)
    )
  end

  private

  def citizen_role_required
    errors.add(:base, "Citizen must have citizen role") unless citizen?
  end

  def ensure_citizen_role
    add_role(:citizen) unless citizen?
  end
end
