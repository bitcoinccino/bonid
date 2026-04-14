# frozen_string_literal: true

class PartnerSchema < ApplicationRecord
  belongs_to :partner
  belongs_to :approved_by, class_name: "AdminUser", optional: true # For approvals by admin

  has_one_attached :cover_image
  has_many :service_applications, dependent: :restrict_with_error

  # === Attribute Types (Rails 8+ native JSON) ===
  attribute :structure, :json, default: {}
  attribute :validation_rules, :json, default: {}

  # === Validations ===
  validates :partner, presence: true
  validates :name, presence: true
  validates :record_type, presence: true
  validates :sector, presence: true
  validates :visibility, inclusion: { in: %w[partner public internal] }
  validates :version, presence: true
  validates :structure, presence: true
  validates :description, length: { maximum: 1000 }, allow_blank: true

  # === Enums / Constants ===
  PRICING_TYPES = %w[free fixed variable].freeze
  SERVICE_CATEGORIES = %w[application appointment transaction survey].freeze
  CURRENCIES = %w[HTG USD].freeze

  FIELD_TYPES = %w[text number currency email phone select radio multi_checkbox checkbox file date time textarea calculated section instructional_text address bonid_signature seal_placeholder].freeze

  validates :pricing_type, inclusion: { in: PRICING_TYPES }, allow_nil: true
  validates :service_category, inclusion: { in: SERVICE_CATEGORIES }, allow_nil: true
  validates :form_code, length: { maximum: 50 }, allow_blank: true
  validates :form_revision, length: { maximum: 20 }, allow_blank: true

  # === Scopes ===
  scope :templates, -> { where(template: true) }
  scope :admin_templates, -> { where(template: true, partner_id: nil) } # global templates
  scope :by_sector, ->(sector) { where(sector: sector) }
  scope :active, -> { where(active: true) }
  scope :for_record_type, ->(type) { where(record_type: type) }
  scope :citizen_services, -> { where(citizen_facing: true, active: true) }

  # Schema status scopes
  scope :draft_status,     -> { where(schema_status: "draft") }
  scope :published_status, -> { where(schema_status: "published") }
  scope :archived_status,  -> { where(schema_status: "archived") }

  # === Callbacks ===
  before_create :assign_version_number
  before_create :auto_generate_form_code

  # === Methods ===

  def approved!(admin)
    update!(active: true, approved_by: admin, approved_at: Time.current)
  end

  def deactivated!
    update!(active: false)
  end

  # Returns the full form code with revision, e.g. "DGI-F008-201908"
  def form_code_display
    return nil if form_code.blank?
    [form_code, form_revision].compact_blank.join("-")
  end

  def price_display
    fields = Array(structure&.dig("fields"))
    has_option_pricing = fields.any? { |f| f["has_pricing"] }

    if price_cents.to_i.zero? && !has_option_pricing
      return "Gratis"
    end

    if has_option_pricing
      # Find the lowest priced option across all priced fields
      # Options are stored as [{label, value, extra_price}, ...]
      min_price = fields.select { |f| f["has_pricing"] }.flat_map { |f|
        opts = f["options"]
        if opts.is_a?(Array)
          opts.map { |o| o["extra_price"].to_f }
        elsif opts.is_a?(String)
          [] # comma-separated strings don't have prices
        else
          []
        end
      }.select(&:positive?).min

      if min_price
        cur = currency || "HTG"
        base = price_cents.to_i > 0 ? (price_cents.to_d / 100) : 0
        starting = base + min_price
        formatted = starting.to_i == starting ? starting.to_i : starting.round(2)
        return "Depi #{formatted} #{cur}"
      end
    end

    return "Varyab" if pricing_type == "variable"

    formatted = price_cents.to_d / 100
    "#{formatted.to_i == formatted ? formatted.to_i : formatted} #{currency || 'HTG'}"
  end

  # Returns pricing metadata from structure JSON
  def price_metadata
    structure&.dig("price_metadata") || {}
  end

  # Calculates the total mandatory cost (base + fees) in centimes.
  # Does NOT include optional field add-ons — those depend on citizen choices.
  def total_price_in_cents
    base = price_cents.to_i
    fees = price_metadata["mandatory_fees"] || []

    fees.each do |fee|
      case fee["kind"] || fee["type"]
      when "percent", "percentage"
        base += (price_cents.to_i * (fee["value"] || fee["amount"] || 0).to_f / 100).round
      when "fixed"
        base += ((fee["value"] || fee["amount"] || 0).to_f * 100).round
      end
    end

    base
  end

  # Human-readable total with breakdown
  def total_price_display
    total = total_price_in_cents
    return "Gratis" if total.zero?

    cur = currency || "HTG"
    formatted = (total.to_d / 100).round(2)
    "#{formatted.to_i == formatted ? formatted.to_i : formatted} #{cur}"
  end

  # Returns optional add-on fields (fields with extra_price on their options)
  def priced_fields
    fields.select do |f|
      opts = f["options"]
      opts.is_a?(Array) && opts.any? { |o| o.is_a?(Hash) && o["extra_price"].to_f > 0 }
    end
  end

  def fields
    Array(structure&.dig("fields"))
  end

  def steps
    Array(structure&.dig("steps"))
  end

  # Returns fields grouped by step for multi-step rendering
  def fields_by_step
    all_fields = fields
    all_steps = steps

    return [{ name: "Fòm", fields: all_fields }] if all_steps.empty?

    result = []
    all_steps.each do |step|
      step_fields = all_fields.select { |f| f["step"] == step["key"] }
      result << { name: step["name"], key: step["key"], fields: step_fields }
    end

    # Any orphan fields without a step go into the first step
    orphans = all_fields.select { |f| f["step"].blank? }
    if orphans.any? && result.any?
      result.first[:fields] = orphans + result.first[:fields]
    elsif orphans.any?
      result.unshift({ name: "Fòm", fields: orphans })
    end

    result
  end

  def fork_for(partner)
    dup.tap do |copy|
      copy.partner = partner
      copy.template = false
      copy.save!
    end
  end

  # === Draft / Publish Versioning ===

  # Is this schema currently published and live?
  def published?
    schema_status == "published"
  end

  # Is this a draft (never published or has unpublished changes)?
  def draft?
    schema_status == "draft"
  end

  # Is this an archived historical version?
  def archived?
    schema_status == "archived"
  end

  # Does this schema have unpublished draft changes?
  def has_draft_changes?
    draft_structure.present? && draft_structure != structure
  end

  # Returns the working structure — draft if editing, otherwise live
  def working_structure
    draft_structure.presence || structure
  end

  # Save edits to draft_structure without affecting the live version.
  # Called when a partner edits a published service.
  def save_draft!(new_structure)
    update!(draft_structure: new_structure)
  end

  # Publish the current draft, incrementing the version.
  # - If draft: publishes structure as-is (first publish)
  # - If published with draft_structure: promotes draft to live
  def publish!
    new_structure = draft_structure.presence || structure

    if published?
      # Archive current version before overwriting
      archive_current_version!
    end

    update!(
      structure: new_structure,
      draft_structure: nil,
      schema_status: "published",
      published_at: Time.current,
      version: next_version_number
    )
  end

  # Discard draft changes and revert to the published structure
  def discard_draft!
    update!(draft_structure: nil)
  end

  # Rollback to a previous version (by copying its structure into draft)
  def rollback_to!(previous_version_number)
    old_schema = version_history.find_by(version: previous_version_number)
    raise "Version #{previous_version_number} not found" unless old_schema

    update!(draft_structure: old_schema.structure)
  end

  # All versions of this service (same record_type from same partner)
  def version_history
    partner.partner_schemas
           .where(record_type: record_type)
           .order(version: :desc)
  end

  # === Capacity ===

  # Count of submitted or approved service applications (excludes drafts/cancelled)
  def sold_count
    service_applications.where(status: %w[submitted under_review approved]).count
  end

  # Returns remaining capacity, or nil if no capacity limit is set
  def available_capacity
    return nil if capacity.blank?

    capacity - sold_count
  end

  # The currently live/published version for this service line
  def live_version
    partner.partner_schemas
           .where(record_type: record_type, schema_status: "published")
           .first
  end

  private

  def assign_version_number
    last_version = partner.partner_schemas.where(record_type: record_type).maximum(:version) || 0
    self.version = last_version + 1
  end

  # Create an archived copy of the current live structure before publishing a new version
  def archive_current_version!
    return unless published?

    # Find or update existing archived record for this version
    # (We don't duplicate the row — we just change this one's status after
    #  the new version takes its place. But if we want a full history,
    #  we clone it.)
    clone = dup
    clone.schema_status = "archived"
    clone.draft_structure = nil
    clone.save!
  end

  def next_version_number
    partner.partner_schemas.where(record_type: record_type).maximum(:version).to_i + 1
  end

  # Auto-generate form_code as {partner_slug}-{seq} when not provided
  def auto_generate_form_code
    return if form_code.present?

    slug = partner&.slug.presence || "form"
    seq = partner.partner_schemas.where.not(id: id).count + 1
    self.form_code = "#{slug}-#{seq.to_s.rjust(3, '0')}"
  end
end
