# frozen_string_literal: true

class PartnerSchema < ApplicationRecord
  belongs_to :partner
  belongs_to :approved_by, class_name: "AdminUser", optional: true # For approvals by admin

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

  # === Scopes ===
  scope :templates, -> { where(template: true) }
  scope :admin_templates, -> { where(template: true, partner_id: nil) } # global templates
  scope :by_sector, ->(sector) { where(sector: sector) }
  scope :active, -> { where(active: true) }
  scope :for_record_type, ->(type) { where(record_type: type) }

  # === Callbacks ===
  before_create :assign_version_number

  # === Methods ===

  def approved!(admin)
    update!(active: true, approved_by: admin, approved_at: Time.current)
  end

  def deactivated!
    update!(active: false)
  end

  def fork_for(partner)
    dup.tap do |copy|
      copy.partner = partner
      copy.template = false
      copy.save!
    end
  end

  private

  def assign_version_number
    last_version = partner.partner_schemas.where(record_type: record_type).maximum(:version) || 0
    self.version = last_version + 1
  end
end
