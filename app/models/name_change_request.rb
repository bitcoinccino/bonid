# app/models/name_change_request.rb
class NameChangeRequest < ApplicationRecord
  belongs_to :user
  belongs_to :reviewed_by, class_name: "AdminUser", optional: true

  has_one_attached :supporting_document

  enum :status, { pending: 0, approved: 1, rejected: 2 }

  REASONS = {
    "marriage"    => "Marriage / Union",
    "court_order" => "Court Order",
    "error"       => "Data Entry Error",
    "other"       => "Other"
  }.freeze

  # Fields a citizen can ask to correct (the form shows them as a checklist
  # and only the ticked ones as "current → new").
  FIELDS = %w[first_name middle_name last_name dob].freeze

  # Set by the citizen form: which FIELDS were ticked. Unticked fields keep
  # their current value, so the request only carries real changes.
  attr_writer :change_fields

  def change_fields
    @change_fields || changed_fields
  end

  # ── Validations ──────────────────────────────────────────────
  validates :old_first_name, :old_last_name, presence: true
  validates :new_first_name, :new_last_name, presence: true
  validate  :something_changes, on: :create
  validate  :new_dob_is_plausible, if: -> { new_dob.present? && new_dob != old_dob }
  validates :reason, presence: true, inclusion: { in: REASONS.keys }
  validates :other_reason, presence: true, if: -> { reason == "other" }
  validates :supporting_document, presence: true, on: :create
  validates :rejection_reason, presence: true, if: :rejected?

  # ── Callbacks ────────────────────────────────────────────────
  before_validation :snapshot_old_name, on: :create
  before_validation :keep_unticked_fields, on: :create
  after_save :require_reverification, if: -> { saved_change_to_status? && approved? }

  # ── Scopes ───────────────────────────────────────────────────
  scope :recent_first, -> { order(created_at: :desc) }
  # Approved by a reviewer but not yet written to the user (that happens
  # once the citizen's re-verification with the new document is approved).
  scope :awaiting_application, -> { approved.where(applied_at: nil) }

  # ── Instance Methods ─────────────────────────────────────────
  def old_full_name
    [old_first_name, old_middle_name, old_last_name].compact_blank.join(" ")
  end

  def new_full_name
    [new_first_name, new_middle_name, new_last_name].compact_blank.join(" ")
  end

  def reason_label
    REASONS[reason] || reason&.titleize
  end

  # FIELDS whose new value differs from the old one.
  def changed_fields
    FIELDS.select { |f| changes_field?(f) }
  end

  def changes_field?(field)
    public_send("new_#{field}").presence != public_send("old_#{field}").presence
  end

  def changes_dob?
    changes_field?("dob")
  end

  private

  def snapshot_old_name
    return unless user
    self.old_first_name  = user.first_name
    self.old_middle_name = user.middle_name
    self.old_last_name   = user.last_name
    self.old_dob         = user.dob
  end

  # Unticked fields keep their current value (names are NOT NULL columns).
  def keep_unticked_fields
    return unless @change_fields

    ticked = Array(@change_fields).map(&:to_s) & FIELDS
    (FIELDS - ticked).each { |f| public_send("new_#{f}=", public_send("old_#{f}")) }
  end

  def something_changes
    return if changed_fields.any?

    errors.add(:base, I18n.t("citizen_portal.name_change.errors.nothing_changed"))
  end

  def new_dob_is_plausible
    if new_dob > Date.current
      errors.add(:new_dob, I18n.t("citizen_portal.name_change.errors.dob_future"))
    elsif new_dob > 18.years.ago.to_date
      errors.add(:new_dob, I18n.t("citizen_portal.name_change.errors.dob_adult"))
    elsif new_dob < Date.new(1900, 1, 1)
      errors.add(:new_dob, I18n.t("citizen_portal.name_change.errors.dob_too_old"))
    end
  end

  # Admin approval does NOT apply the name change immediately.
  # Instead, it marks the request as pre-approved and requires
  # the citizen to reverify with a new CIN/passport showing the new name.
  def require_reverification
    Rails.logger.info "[NameChangeRequest] Pre-approved for user ##{user.id}. Suspending BonID until reverification."

    # 1. Suspend the active submission — BonID is no longer valid until reverified
    submission = user.identity_submissions.where(status: :approved).order(verified_at: :desc).first
    if submission
      submission.update_columns(status: IdentitySubmission.statuses[:revoked])
      Rails.logger.info "[NameChangeRequest] Submission ##{submission.id} suspended (revoked) pending reverification"
    end

    # 2. Invalidate cached API responses
    Rails.cache.delete("api:identity:#{user.bonid}") if user.bonid.present?

    # 3. Notify partners with active consents
    user.consent_grants.where(status: :approved).find_each do |grant|
      ConsentWebhookJob.perform_later(grant.id, "bonid.suspended") rescue nil
    end

    # 4. Notify citizen: name change approved, BonID suspended, please reverify
    Citizens::NameChangeMailer.with(
      user: user,
      name_change_request: self
    ).reverification_required.deliver_later rescue nil
  end

  # Called AFTER the citizen completes a reissue submission with new documents.
  # This is triggered by the admin approving the reissue submission,
  # NOT by approving the name change request.
  def apply_name_change!
    old_bonid = user.bonid

    # 1. Update the user's name (and date of birth when corrected)
    attrs = {
      first_name:  new_first_name,
      middle_name: new_middle_name,
      last_name:   new_last_name
    }
    attrs[:dob] = new_dob if changes_dob?
    user.update_columns(attrs)

    # 2. Regenerate BonID code (initials and birth year are part of it)
    user.reload
    new_bonid = user.generate_bonid!

    unless new_bonid.present?
      Rails.logger.error "[NameChangeRequest] BonID regeneration failed for user ##{user.id} — bonid unchanged: #{old_bonid}"
      update_column(:applied_at, Time.current)
      return
    end

    Rails.logger.info "[NameChangeRequest] BonID updated for user ##{user.id}: #{old_bonid} -> #{new_bonid}"

    # 3. Create BonID alias so old BonID still resolves via Identity API
    if old_bonid.present? && old_bonid != new_bonid
      BonidAlias.create!(
        user:      user,
        old_bonid: old_bonid,
        new_bonid: new_bonid,
        reason:    "name_change"
      )
      Rails.logger.info "[NameChangeRequest] BonID alias created: #{old_bonid} -> #{new_bonid}"

      Rails.cache.delete("api:identity:#{old_bonid}")

      user.consent_grants.where(status: :approved).find_each do |grant|
        ConsentWebhookJob.perform_later(grant.id, "bonid.changed") rescue nil
      end
    end

    # 4. Update the active submission with new BonID and regenerate QR
    submission = user.identity_submissions.where(status: :approved).order(verified_at: :desc).first
    if submission
      submission.update_columns(bonid: new_bonid)
      submission.regenerate_combined_qr!
      Rails.logger.info "[NameChangeRequest] Synced submission ##{submission.id} with new BonID & name"
    end

    # 5. Mark this request as fully applied
    update_column(:applied_at, Time.current)
  end

  # Called by IdentitySubmission once the re-verification is approved, so it
  # must be public (it sat under `private` and could never run).
  public :apply_name_change!
end
