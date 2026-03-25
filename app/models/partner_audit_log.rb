class PartnerAuditLog < ApplicationRecord
  belongs_to :partner, optional: true
  belongs_to :admin_user, optional: true

  # ---------------------------------------------------------------------------
  # CLASS METHOD: Unified audit logger
  # ---------------------------------------------------------------------------
  def self.log!(partner, actor, event, details = {})
    create!(
      partner: partner,
      admin_user: actor.is_a?(AdminUser) ? actor : nil,
      event: event,
      details: details
    )
  end
end
