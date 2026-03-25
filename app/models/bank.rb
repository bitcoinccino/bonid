# frozen_string_literal: true

class Bank < ApplicationRecord
  has_many :bank_profiles

  validates :name, presence: true
  validates :swift_code, presence: true, uniqueness: true
  validates :slug, presence: true

  scope :verified, -> { where(verified_partner: true) }
  scope :alphabetical, -> { order(:name) }

  # Lookup bank by name (case-insensitive, partial match)
  scope :lookup_by_name, ->(name) {
    where("LOWER(name) LIKE ?", "%#{name.downcase}%")
  }
end
