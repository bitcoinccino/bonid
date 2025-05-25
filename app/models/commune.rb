class Commune < ApplicationRecord
  belongs_to :department
  belongs_to :arrondissement
  has_many :communal_sections
  validates :postal_code, presence: true
end