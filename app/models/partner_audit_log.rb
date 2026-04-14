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
      details: details.is_a?(Hash) ? details.to_json : details,
      metadata: details.is_a?(Hash) ? details : {}
    )
  end
end
