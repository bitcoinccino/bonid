class PersonInvolvement < ApplicationRecord
  belongs_to :incident_report, inverse_of: :person_involvements
  belongs_to :user, optional: true
  belongs_to :visitor_submission, optional: true

  has_one :address, as: :addressable, dependent: :destroy, inverse_of: :addressable
  accepts_nested_attributes_for :address, allow_destroy: true, reject_if: :all_blank

  # ======================
  # Attribute Declarations
  # ======================
  attribute :id_type, :string
  attribute :first_name, :string
  attribute :middle_name, :string
  attribute :last_name, :string
  attribute :cin, :string
  attribute :cin_unique_id, :string
  attribute :phone, :string
  attribute :email, :string
  attribute :passport_number, :string
  attribute :issuing_authority, :string
  attribute :sex, :string
  attribute :nationality, :string
  attribute :date_of_birth, :date
  attribute :id_issued_on, :date
  attribute :id_expires_on, :date
  attribute :place_of_birth_department_id, :integer
  attribute :place_of_birth_commune_id, :integer

  # ======================
  # Enums
  # ======================
  enum :role, {
    suspect: 0,
    victim: 1,
    witness: 2,
    innocent: 3,
    unknown: 4,
    accomplice: 5
  }, prefix: true

  enum :id_type, { cin: "cin", passport: "passport" }, prefix: true

  enum :status, {
    # Active Pursuit (Suspect/Accomplice)
    in_custody: "In Custody",
    fugitive: "Fugitive",
    wanted: "Wanted",
    under_surveillance: "Under Surveillance",
    identity_unknown: "Identity Unknown",

    # In System (Suspect/Accomplice)
    detained_awaiting_charges: "Detained Awaiting Charges",
    escaped_custody: "Escaped Custody",
    released_on_bail: "Released on Bail",

    # Risk Factors (Suspect/Accomplice)
    armed: "Armed",
    dangerous: "Dangerous",
    mentally_unstable: "Mentally Unstable",

    # Legal Outcomes (Admin only)
    awaiting_trial: "Awaiting Trial",
    convicted: "Convicted",
    acquitted: "Acquitted",
    exonerated: "Exonerated",
    probation: "On Probation",
    paroled: "Paroled",
    released_no_charges: "Released Without Charges",
    transferred: "Transferred",
    expunged_record: "Record Expunged",

    # Physical State (Victim/Witness/Civilian)
    deceased: "Deceased",
    missing: "Missing",
    known_location: "Known Location",

    # Engagement (Victim/Witness)
    cooperating: "Cooperating",
    under_investigation: "Under Investigation",
    protected: "Protected"
  }, prefix: true

  # ======================
  # Role-Based Status Groups
  # ======================

  # Suspect & Accomplice statuses (legal & risk tracking)
  SUSPECT_STATUSES = %w[
    in_custody fugitive identity_unknown detained_awaiting_charges escaped_custody
    wanted armed dangerous mentally_unstable released_on_bail awaiting_trial
    convicted acquitted exonerated probation paroled under_surveillance
  ].freeze

  # Victim & Witness statuses (safety & participation)
  CIVILIAN_STATUSES = %w[
    deceased missing cooperating known_location identity_unknown
    under_investigation under_surveillance protected released_no_charges
  ].freeze

  # Innocent statuses (administrative - cleared individuals)
  INNOCENT_STATUSES = %w[
    released_no_charges acquitted exonerated deceased expunged_record
  ].freeze

  # Status-to-role mapping for validation
  VALID_STATUSES_FOR_ROLE = {
    "suspect" => SUSPECT_STATUSES,
    "accomplice" => SUSPECT_STATUSES,
    "victim" => CIVILIAN_STATUSES,
    "witness" => CIVILIAN_STATUSES,
    "innocent" => INNOCENT_STATUSES,
    "unknown" => [] # No status required for unknown role
  }.freeze

  # Statuses officers can assign (subset by role)
  OFFICER_ASSIGNABLE_STATUSES = {
    "suspect" => %w[
      in_custody fugitive identity_unknown detained_awaiting_charges
      escaped_custody wanted armed dangerous mentally_unstable
      cooperating missing under_investigation
    ],
    "accomplice" => %w[
      in_custody fugitive identity_unknown detained_awaiting_charges
      escaped_custody wanted armed dangerous mentally_unstable
      cooperating missing under_investigation
    ],
    "victim" => %w[
      deceased missing cooperating known_location identity_unknown
      under_investigation protected
    ],
    "witness" => %w[
      cooperating known_location identity_unknown
      under_investigation protected missing
    ],
    "innocent" => %w[released_no_charges deceased],
    "unknown" => []
  }.freeze

  # Admin-only statuses (legal outcomes requiring higher authority)
  ADMIN_ONLY_STATUSES = %w[
    released_on_bail awaiting_trial convicted acquitted exonerated
    probation paroled released_no_charges transferred under_surveillance
    expunged_record
  ].freeze

  # Admin-only innocent statuses (court-validated or legal outcomes)
  ADMIN_ONLY_INNOCENT_STATUSES = %w[acquitted exonerated expunged_record].freeze

  # Legacy constant for backwards compatibility
  OFFICER_STATUSES = OFFICER_ASSIGNABLE_STATUSES.values.flatten.uniq.freeze
  ADMIN_STATUSES = statuses.keys - OFFICER_STATUSES

  # ======================
  # Validations
  # ======================
  validates :role, presence: true
  validates :bonid, presence: true, unless: :no_bonid
  validates :first_name, :last_name, presence: true, if: :no_bonid
  validates :sex, :date_of_birth, :id_type, :nationality, presence: true, if: :no_bonid
  validates :address, presence: true, if: :no_bonid

  validate :status_required_for_identified_suspects
  validate :status_valid_for_role
  validate :address_must_be_complete, if: :no_bonid
  validate :no_duplicate_person_in_report

  before_validation :set_default_role, on: :create

  # ======================
  # Methods
  # ======================

  def locked_primary?
    user_id.present? && role == "suspect"
  end

  # Returns true if this person is a tourist (BonTouris holder)
  def tourist?
    visitor_submission_id.present? || bonid&.start_with?("T-")
  end

  # Returns true if this person is a citizen (BonID holder)
  def citizen?
    user_id.present? && !tourist?
  end

  # Returns valid statuses for a given role
  # @param role [String, Symbol] The role to get statuses for
  # @param officer_only [Boolean] If true, returns only officer-assignable statuses
  # @return [Array<String>] List of valid status keys
  def self.statuses_for_role(role, officer_only: false)
    role_key = role.to_s
    if officer_only
      OFFICER_ASSIGNABLE_STATUSES[role_key] || []
    else
      VALID_STATUSES_FOR_ROLE[role_key] || []
    end
  end

  # Returns status options formatted for select dropdowns
  # @param role [String, Symbol] The role to get statuses for
  # @param officer_only [Boolean] If true, returns only officer-assignable statuses
  # @return [Array<Array>] Array of [label, value] pairs for select options
  def self.status_options_for_role(role, officer_only: false)
    valid_keys = statuses_for_role(role, officer_only: officer_only)
    statuses.slice(*valid_keys).map { |key, label| [ label, key ] }
  end

  private

  def set_default_role
    self.role ||= "unknown"
  end

  def status_required_for_identified_suspects
    if %w[suspect accomplice].include?(role) && bonid.present? && status.blank?
      errors.add(:status, "must be specified for suspects and accomplices with BonID")
    end
  end

  def status_valid_for_role
    return if status.blank? || role.blank?
    return if role == "unknown" # Unknown role has no status restrictions

    valid_statuses = VALID_STATUSES_FOR_ROLE[role]
    return if valid_statuses.blank?

    unless valid_statuses.include?(status)
      valid_labels = valid_statuses.map { |s| self.class.statuses[s] }.compact.join(", ")
      errors.add(:status, "\"#{self.class.statuses[status]}\" is not valid for #{role.humanize} role. " \
                 "Valid options: #{valid_labels}")
    end
  end

  def address_must_be_complete
    return unless address.present?

    if address.commune_id.blank?
      errors.add(:address, "must include a commune")
      address.errors.add(:commune_id, "can't be blank")
    end

    if address.communal_section_id.blank?
      errors.add(:address, "must include a communal section")
      address.errors.add(:communal_section_id, "can't be blank")
    end
  end

  # Prevent adding the same person twice to the same incident report
  # This checks both persisted records AND in-memory (unpersisted) associations
  def no_duplicate_person_in_report
    return if incident_report.blank?

    # Get all other person involvements (exclude self by object_id for new records, id for persisted)
    other_involvements = incident_report.person_involvements.reject do |pi|
      pi.equal?(self) || (id.present? && pi.id == id)
    end

    # Exclude destroyed records (marked with _destroy flag)
    other_involvements = other_involvements.reject(&:marked_for_destruction?)

    # Check for duplicate citizen (user_id)
    if user_id.present? && other_involvements.any? { |pi| pi.user_id == user_id }
      errors.add(:base, "This citizen (BonID holder) is already involved in this incident report")
    end

    # Check for duplicate tourist (visitor_submission_id)
    if visitor_submission_id.present? && other_involvements.any? { |pi| pi.visitor_submission_id == visitor_submission_id }
      errors.add(:base, "This tourist (BonTouris holder) is already involved in this incident report")
    end

    # Check for duplicate by bonid string (for cases where user_id is not set but bonid is)
    if bonid.present? && user_id.blank? && visitor_submission_id.blank?
      if other_involvements.any? { |pi| pi.bonid == bonid && pi.user_id.blank? && pi.visitor_submission_id.blank? }
        errors.add(:base, "This person (BonID: #{bonid}) is already involved in this incident report")
      end
    end
  end
end


# app/models/person_involvement.rb
class PersonInvolvement < ApplicationRecord
  include CrimeConstants
  include OfficerConstants

  belongs_to :incident_report, inverse_of: :person_involvements
  belongs_to :user, optional: true
  belongs_to :visitor_submission, optional: true

  has_one :address, as: :addressable, dependent: :destroy, inverse_of: :addressable
  accepts_nested_attributes_for :address, allow_destroy: true, reject_if: :all_blank

  # ======================
  # Attribute Declarations
  # ======================
  # ... (Attributes remain as defined in your prompt) ...

  # ======================
  # Enums & Status Groups
  # ======================
  # ... (Enums, SUSPECT_STATUSES, CIVILIAN_STATUSES, etc., remain as defined) ...

  # ======================
  # Validations
  # ======================
  validates :role, presence: true
  validates :bonid, presence: true, unless: :no_bonid
  validates :first_name, :last_name, presence: true, if: :no_bonid
  validates :sex, :date_of_birth, :id_type, :nationality, presence: true, if: :no_bonid

  validate :status_required_for_identified_suspects
  validate :status_valid_for_role
  validate :address_must_be_complete, if: :no_bonid
  validate :restricted_status_assignment, on: :update

  before_validation :set_default_role, on: :create

  # ======================
  # Risk & Assessment Logic
  # ======================

  # Calculates the dynamic risk score for this individual
  # @return [Hash] contains level (string) and score (integer)
  def risk_assessment
    # 1. Base risk from CrimeConstants based on Role + Crime Type
    base_level = CrimeConstants.calculate_risk(role, incident_report.crime_type)

    # 2. Risk Escalation based on Status
    # Even a "Low" severity crime becomes "High" risk if the person is "Armed"
    final_level = case status
    when "armed", "dangerous", "escaped_custody", "wanted", "fugitive"
                    "high"
    when "mentally_unstable", "under_surveillance"
                    base_level == "none" ? "low" : "medium"
    when "exonerated", "acquitted", "expunged_record", "innocent"
                    "none"
    else
                    base_level
    end

    # 3. Numeric Score Mapping
    score_map = { "none" => 0, "low" => 1, "medium" => 3, "high" => 5 }

    {
      level: final_level,
      score: score_map[final_level] || 0
    }
  end

  # ======================
  # Instance Methods
  # ======================

  def locked_primary?
    user_id.present? && role == "suspect"
  end

  def tourist?
    visitor_submission_id.present? || bonid&.start_with?("T-")
  end

  def citizen?
    user_id.present? && !tourist?
  end

  private

  def set_default_role
    self.role ||= "unknown"
  end

  # Ensures only admins/higher-ups can set legal outcomes (Bail, Convicted, etc.)
  def restricted_status_assignment
    return unless status_changed?

    # Logic to check if the current actor has permission (Assumes Current.user or similar)
    if defined?(Current) && Current.user&.role != "admin" && ADMIN_ONLY_STATUSES.include?(status)
      errors.add(:status, "requires judicial authorization for '#{self.class.statuses[status]}'")
    end
  end

  def status_required_for_identified_suspects
    if %w[suspect accomplice].include?(role) && bonid.present? && status.blank?
      errors.add(:status, "must be specified for identified suspects/accomplices")
    end
  end

  def status_valid_for_role
    return if status.blank? || role.blank? || role == "unknown"

    valid_statuses = VALID_STATUSES_FOR_ROLE[role]
    unless valid_statuses&.include?(status)
      errors.add(:status, "is not a valid legal state for a #{role.humanize}")
    end
  end

  def address_must_be_complete
    if address.blank? || address.commune_id.blank? || address.communal_section_id.blank?
      errors.add(:address, "is incomplete. Full location required for new records.")
    end
  end

  def no_duplicate_person_in_report
    # Prevents adding the same BonID twice to the same report
    if incident_report.person_involvements.where(bonid: bonid).where.not(id: id).exists?
      errors.add(:bonid, "is already listed in this incident report")
    end
  end
end
