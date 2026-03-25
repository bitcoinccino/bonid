# app/models/crime_category.rb
class CrimeCategory < ApplicationRecord
  has_many :crime_types, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :code, presence: true, uniqueness: true, length: { maximum: 10 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:display_order, :name) }

  # Class method to get categories for select dropdown
  def self.for_select
    active.ordered.pluck(:name, :id)
  end

  def to_s
    name
  end
end
