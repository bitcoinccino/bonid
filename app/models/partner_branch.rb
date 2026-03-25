class PartnerBranch < ApplicationRecord
  belongs_to :partner
  has_one :address, as: :addressable, dependent: :destroy

  accepts_nested_attributes_for :address

  validates :name, presence: true
  validates :partner_id, presence: true

  scope :active, -> { where(active: true) }

  delegate :full_formatted, to: :address, allow_nil: true
end
