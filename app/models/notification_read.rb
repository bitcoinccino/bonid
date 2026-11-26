# frozen_string_literal: true

# A citizen opened one bell notification (see Citizens::AlertCounter).
class NotificationRead < ApplicationRecord
  KEY_FORMAT = /\A(scan|consent|txn|app|device):[A-Za-z0-9_:]+\z/

  belongs_to :user

  validates :key, presence: true, length: { maximum: 100 }, format: { with: KEY_FORMAT }

  # Idempotent: opening the same notification twice is fine.
  def self.mark!(user, key)
    create!(user: user, key: key)
  rescue ActiveRecord::RecordNotUnique
    true
  end
end
