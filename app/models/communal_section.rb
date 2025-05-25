class CommunalSection < ApplicationRecord
  belongs_to :commune
  validates :postal_code, presence: true
  has_many :addresses, dependent: :destroy
end
