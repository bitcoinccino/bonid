# app/models/partner_access_log.rb
class PartnerAccessLog < ApplicationRecord
  belongs_to :partner
  belongs_to :admin_user, optional: true

  validates :action, presence: true

  # --- Scopes ---
  scope :recent, -> { order(created_at: :desc) }
  scope :for_partner, ->(partner) { where(partner:) }

  # --- Helpers ---
  def display_action
    action.titleize
  end

  def timestamp
    created_at.strftime("%Y-%m-%d %H:%M:%S")
  end
end
