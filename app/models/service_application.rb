# frozen_string_literal: true

# ServiceApplication stores a citizen's submitted data for a partner service.
# It is locked to the exact PartnerSchema version (schema_snapshot) that existed
# when the citizen started the application, ensuring form changes never break
# in-flight submissions.
class ServiceApplication < ApplicationRecord
  belongs_to :citizen, class_name: "User"
  belongs_to :partner
  belongs_to :partner_schema
  belongs_to :reviewed_by, class_name: "User", optional: true

  # Real-time citizen bell — fires on create and on status flips so the
  # citizen sees both fresh applications and reviewer decisions in real time.
  after_create_commit :broadcast_alert_to_citizen
  after_update_commit :broadcast_alert_to_citizen, if: :saved_change_to_status?

  def broadcast_alert_to_citizen
    Citizens::AlertBroadcastJob.perform_later(citizen_id) if citizen_id
  end

  # File uploads from "file" type fields
  has_many_attached :documents

  # The generated signed/sealed PDF
  has_one_attached :pdf_document

  # === Attribute Types ===
  attribute :form_data, :json, default: {}
  attribute :calculated_values, :json, default: {}
  attribute :schema_snapshot, :json, default: {}

  # === Constants ===
  STATUSES = %w[draft submitted under_review approved rejected cancelled].freeze

  # === Validations ===
  validates :status, inclusion: { in: STATUSES }
  validates :schema_version, presence: true
  validates :verification_code, presence: true, uniqueness: true

  # === Scopes ===
  scope :drafts,       -> { where(status: "draft") }
  scope :submitted,    -> { where(status: "submitted") }
  scope :under_review, -> { where(status: "under_review") }
  scope :approved,     -> { where(status: "approved") }
  scope :rejected,     -> { where(status: "rejected") }
  scope :active,       -> { where(status: %w[draft submitted under_review]) }
  scope :completed,    -> { where(status: %w[approved rejected]) }

  # Status predicates
  STATUSES.each { |s| define_method(:"#{s}?") { status == s } }
  scope :for_partner,  ->(partner) { where(partner: partner) }
  scope :for_citizen,  ->(citizen) { where(citizen: citizen) }

  # === Callbacks ===
  before_validation :generate_verification_code, on: :create
  before_validation :snapshot_schema, on: :create

  # === Status Transitions ===

  def submit!
    raise "Can only submit draft applications" unless status == "draft"

    update!(
      status: "submitted",
      submitted_at: Time.current
    )
  end

  def start_review!(reviewer)
    raise "Can only review submitted applications" unless status == "submitted"

    update!(
      status: "under_review",
      reviewed_by: reviewer,
      reviewed_at: Time.current
    )
  end

  def approve!(reviewer)
    raise "Can only approve applications under review" unless status.in?(%w[submitted under_review])

    attrs = {
      status: "approved",
      reviewed_by: reviewer,
      reviewed_at: Time.current
    }

    # Auto-apply seal if schema requires it
    if partner_schema.auto_stamp? && partner.seal_image.attached?
      attrs[:sealed] = true
      attrs[:sealed_at] = Time.current
      attrs[:seal_checksum] = generate_seal_checksum
    end

    update!(attrs)
  end

  def reject!(reviewer, reason: nil)
    raise "Can only reject applications under review" unless status.in?(%w[submitted under_review])

    update!(
      status: "rejected",
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      rejection_reason: reason
    )
  end

  def cancel!
    raise "Cannot cancel completed applications" if status.in?(%w[approved rejected])

    update!(status: "cancelled")
  end

  # === Schema Snapshot ===

  # Returns the frozen structure from when the citizen started
  def frozen_fields
    Array(schema_snapshot&.dig("fields"))
  end

  def frozen_steps
    Array(schema_snapshot&.dig("steps"))
  end

  # Returns fields by step from the frozen snapshot
  def frozen_fields_by_step
    all_fields = frozen_fields
    all_steps = frozen_steps

    return [ { name: "Fòm", fields: all_fields } ] if all_steps.empty?

    result = []
    all_steps.each do |step|
      step_fields = all_fields.select { |f| f["step"] == step["key"] }
      result << { name: step["name"], key: step["key"], fields: step_fields }
    end

    orphans = all_fields.select { |f| f["step"].blank? }
    if orphans.any? && result.any?
      result.first[:fields] = orphans + result.first[:fields]
    elsif orphans.any?
      result.unshift({ name: "Fòm", fields: orphans })
    end

    result
  end

  # === Helpers ===

  def price_display
    return "Gratis" if total_price_cents.to_i.zero?

    formatted = total_price_cents.to_d / 100
    "#{formatted.to_i == formatted ? formatted.to_i : formatted} #{currency || 'HTG'}"
  end

  def signed?
    signature_consented? && signature_applied_at.present?
  end

  def pdf_ready?
    pdf_document.attached? && pdf_generated_at.present?
  end

  def status_label
    {
      "draft" => "Bouyon",
      "submitted" => "Soumèt",
      "under_review" => "Ap Revize",
      "approved" => "Apwouve",
      "rejected" => "Rejte",
      "cancelled" => "Anile"
    }[status] || status
  end

  private

  def generate_verification_code
    self.verification_code ||= "SA-#{SecureRandom.hex(4).upcase}-#{Time.current.strftime('%y%m')}"
  end

  def snapshot_schema
    return if schema_snapshot.present? && schema_snapshot["fields"].present?

    self.schema_version = partner_schema.version
    self.schema_snapshot = partner_schema.structure.deep_dup
  end

  def generate_seal_checksum
    secret = Rails.application.credentials.hmac_secret || "bonid-seal-fallback"
    data = "#{id}:#{partner_id}:#{citizen_id}:#{verification_code}"
    OpenSSL::HMAC.hexdigest("SHA256", secret, data)
  end
end
