# app/models/role.rb
class Role < ApplicationRecord
  scopify

  has_and_belongs_to_many :users, join_table: :users_roles
  belongs_to :resource, polymorphic: true, optional: true

  # ==========================================================================
  # 🚨 MASTER ROLE LIST — CLEAN, CONSISTENT, FUTURE-PROOF
  # ==========================================================================

  NAMES = %w[
    citizen
    partner_admin
    partner_agent
    partner_agent_surveyor
    partner_agent_notary
    partner_supervisor
    bank_agent
    bank_supervisor
    bank_teller
    officer
    reviewer
    admin_user
    law_enforcement
    embassy
    hospital
  ].freeze

  # ==========================================================================
  # VALIDATIONS
  # ==========================================================================
  validates :name,
            presence: true,
            uniqueness: { case_sensitive: false },
            inclusion: { in: NAMES }

  validates :slug,
            presence: true,
            uniqueness: true

  # ==========================================================================
  # CALLBACKS
  # ==========================================================================
  before_validation :normalize_name_and_slug

  # ==========================================================================
  # SCOPES
  # ==========================================================================
  scope :citizen,         -> { where(name: "citizen") }
  scope :partner_admin,   -> { where(name: "partner_admin") }
  scope :partner_agent,   -> { where(name: "partner_agent") }
  scope :officer,         -> { where(name: "officer") }
  scope :reviewer,        -> { where(name: "reviewer") }
  scope :admin_user,      -> { where(name: "admin_user") }
  scope :law_enforcement, -> { where(name: "law_enforcement") }
  scope :embassy,         -> { where(name: "embassy") }
  scope :hospital,        -> { where(name: "hospital") }

  scope :system_roles,    -> { where(system_role: true) }
  scope :for_resource,    ->(resource) { where(resource: resource) }

  # ==========================================================================
  # INSTANCE METHODS
  # ==========================================================================
  def system?
    system_role
  end

  private

  def normalize_name_and_slug
    self.name = name.downcase if name.present?
    self.slug = name.parameterize if name.present? && slug.blank?
  end
end
