class CitizenProfile < ApplicationRecord
  # devise :invitable, :database_authenticatable, :recoverable, :rememberable, :validatable,
  #        :trackable, :timeoutable

  belongs_to :user
  has_many :citizen_sessions, dependent: :destroy
  # Optional: validations for citizen data
  validates :bonid, uniqueness: true, allow_nil: true
end
