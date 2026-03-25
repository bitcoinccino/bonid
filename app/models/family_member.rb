# frozen_string_literal: true

# FamilyMember — optional parent/guardian records for a BonID citizen.
#
# Used by:
#   - Archives Nationales (civil_registry) — birth certificate matching
#   - ONACA (land_registry) — inheritance / property chain of custody
#   - Tribunals (judicial_record) — inheritance disputes, pension claims
#
# Citizens add these optionally in their profile, or when prompted
# by a transaction consent that requires family data (e.g. civil_registry).
#
# If the family member also has a BonID, the citizen can link them.
# The linked person must approve via consent (both-way consent).
#
class FamilyMember < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :user                                          # the citizen
  belongs_to :linked_user, class_name: "User", optional: true  # the parent/guardian's own account
  belongs_to :birth_department, class_name: "Department", optional: true
  belongs_to :birth_commune, class_name: "Commune", optional: true

  # ============================================================
  # ENUMS
  # ============================================================
  enum :relationship, {
    mother: 0,
    father: 1,
    guardian: 2,
    legal_representative: 3
  }

  enum :verification_status, {
    manual_entry: 0,
    pending_confirmation: 1,
    verified: 2
  }, prefix: :link

  # Guardian sub-types (Haitian family structures)
  GUARDIAN_TYPES = %w[
    marenn_parann
    granmoun
    tonton
    matant
    lokal
    legal
  ].freeze

  GUARDIAN_TYPE_LABELS = {
    "marenn_parann" => "Marenn / Parann (Godparent)",
    "granmoun"      => "Granmoun (Elder/Grandparent)",
    "tonton"        => "Tonton (Uncle)",
    "matant"        => "Matant (Aunt)",
    "lokal"         => "Lokal (Neighbor/Community)",
    "legal"         => "Reprezantan Legal (Legal Guardian)"
  }.freeze

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :relationship, presence: true

  # A citizen can only have one mother and one father
  validates :relationship, uniqueness: {
    scope: :user_id,
    message: "already exists for this citizen"
  }, if: -> { mother? || father? }

  # Cannot link yourself as your own parent/guardian
  validate :cannot_link_self
  validate :cannot_link_self_by_bonid
  validate :cannot_relink_denied_person
  validate :sex_matches_relationship
  validate :linked_user_must_exist, if: -> { linked_bonid.present? && linked_user_id.blank? }
  validates :guardian_type, inclusion: { in: GUARDIAN_TYPES }, allow_blank: true
  validate :death_date_required_if_deceased

  # ============================================================
  # CALLBACKS
  # ============================================================
  before_save :resolve_linked_bonid, if: -> { linked_bonid.present? && linked_user_id.blank? }
  after_commit :send_link_notification, on: [:create, :update],
               if: -> { linked_user_id.present? && !link_confirmed? && saved_change_to_linked_user_id? }

  # ============================================================
  # SCOPES
  # ============================================================
  scope :parents, -> { where(relationship: [:mother, :father]) }
  scope :guardians, -> { where(relationship: [:guardian, :legal_representative]) }
  scope :linked, -> { where.not(linked_user_id: nil) }
  scope :confirmed_links, -> { where.not(link_confirmed_at: nil) }
  scope :pending_links, -> { where(linked_user_id: nil).where.not(linked_bonid: nil) }

  # ============================================================
  # DISPLAY
  # ============================================================
  def full_name
    [first_name, middle_name, last_name].compact_blank.join(" ")
  end

  def display_relationship
    case relationship
    when "mother" then "Manman"
    when "father" then "Papa"
    when "guardian"
      guardian_type.present? ? GUARDIAN_TYPE_LABELS[guardian_type] : "Gadyen"
    when "legal_representative" then "Reprezantan Legal"
    end
  end

  def deceased?
    !alive?
  end

  def birth_location
    [birth_commune&.name, birth_department&.name].compact.join(", ").presence || place_of_birth
  end

  def linked?
    linked_user_id.present?
  end

  def link_confirmed?
    link_confirmed_at.present?
  end

  # ============================================================
  # BONID LINKING
  # ============================================================

  # Request the linked person's consent to be listed as parent
  def request_link_consent!
    return false unless linked_user.present?
    return true if link_confirmed?

    token = SecureRandom.hex(16)
    update!(
      link_consent_token: token,
      link_consent_sent_at: Time.current
    )
    # TODO: Send SMS/notification to linked_user asking them to confirm
    token
  end

  # The linked person confirms they are this citizen's parent
  def confirm_link!(ip: nil)
    update!(
      link_confirmed_at: Time.current,
      link_consent_token: nil,
      metadata: metadata.merge(
        "link_confirmed_ip" => ip,
        "link_confirmed_at" => Time.current.iso8601
      )
    )
  end

  # ============================================================
  # API SUMMARY (for consent-gated responses)
  # ============================================================
  def summary
    data = {
      relationship: relationship,
      guardian_type: guardian_type,
      first_name: first_name,
      middle_name: middle_name,
      last_name: last_name,
      full_name: full_name,
      date_of_birth: date_of_birth&.iso8601,
      place_of_birth: birth_location,
      nationality: nationality,
      alive: alive,
      date_of_death: date_of_death&.iso8601,
      verification_status: verification_status
    }

    # Only include linked BonID if the link is confirmed (both-way consent)
    if link_confirmed?
      data[:linked_bonid] = linked_bonid
      data[:link_verified] = true
    elsif linked?
      data[:link_pending] = true
    end

    data.compact
  end

  private

  def death_date_required_if_deceased
    if deceased? && date_of_death.blank?
      # Not required — many Haitians don't have exact death dates documented
      # Just a soft nudge in the UI
    end
  end

  def cannot_link_self
    if linked_user_id.present? && linked_user_id == user_id
      errors.add(:linked_user_id, "Ou pa ka ajoute tèt ou kòm fanmi")
    end
  end

  def sex_matches_relationship
    return unless linked_user.present?
    sex = linked_user.sex.to_s.downcase
    is_male = %w[m male].include?(sex)
    is_female = %w[f female].include?(sex)
    if mother? && is_male
      errors.add(:linked_bonid, "#{linked_user.first_name} se gason. Ou pa ka mete li kòm Manman.")
    elsif father? && is_female
      errors.add(:linked_bonid, "#{linked_user.first_name} se fi. Ou pa ka mete li kòm Papa.")
    end
  end

  def cannot_relink_denied_person
    return if linked_user_id.blank?
    denied_id = metadata&.dig("denied_user_id")
    if denied_id.present? && denied_id.to_i == linked_user_id
      errors.add(:linked_bonid, "Moun sa a deja refize relasyon sa a. Ou pa ka voye demann ankò.")
    end
  end

  def cannot_link_self_by_bonid
    return if linked_bonid.blank? || user.blank?
    own_bonid = user.bonid.to_s.gsub("-", "").upcase
    input_bonid = linked_bonid.to_s.gsub("-", "").upcase
    if own_bonid.present? && (input_bonid == own_bonid || own_bonid.end_with?(input_bonid))
      errors.add(:linked_bonid, "Ou pa ka ajoute tèt ou kòm fanmi")
    end
  end

  def linked_user_must_exist
    found = find_user_by_bonid_or_suffix(linked_bonid)
    unless found
      errors.add(:linked_bonid, "BonID pa jwenn pou '#{linked_bonid}'")
    end
  end

  def send_link_notification
    NotifyFamilyLinkJob.perform_later(family_member_id: id)
  end

  def resolve_linked_bonid
    if linked_bonid.present? && linked_user_id.blank?
      found = find_user_by_bonid_or_suffix(linked_bonid)
      if found
        self.linked_user = found
        self.linked_bonid = found.bonid # Store the full BonID
      end
    end
  end

  # Find user by full BonID or last-6 suffix (strips dashes)
  def find_user_by_bonid_or_suffix(input)
    return nil if input.blank?
    clean = input.strip.upcase

    # Try exact match first
    found = User.find_by(bonid: clean)
    return found if found

    # Try suffix match (strip dashes, match last N chars)
    stripped = clean.gsub("-", "")
    if stripped.length >= 6 && stripped.length <= 10
      User.find_each(batch_size: 100) do |u|
        next if u.bonid.blank?
        user_stripped = u.bonid.gsub("-", "").upcase
        return u if user_stripped.end_with?(stripped)
      end

      # Also check identity submissions (old BonID format)
      sub = IdentitySubmission.approved
              .where("REPLACE(UPPER(bonid), '-', '') LIKE ?", "%#{stripped}")
              .includes(:user)
              .first
      return sub.user if sub&.user
    end

    nil
  end
end
