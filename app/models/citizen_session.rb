class CitizenSession < ApplicationRecord
  belongs_to :user
  belongs_to :citizen_profile, optional: true
  validates :login_source, :ip_address, :device_fingerprint, presence: true, unless: -> { Rails.env.development? || Rails.env.test? }
end
