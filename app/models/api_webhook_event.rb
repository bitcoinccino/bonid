class ApiWebhookEvent < ApplicationRecord
  self.table_name = "api_webhook_events"

  belongs_to :partner

  validates :event_type, presence: true
  validates :bonid, presence: true
  validates :retry_attempts, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :failed, -> { where("payload ->> 'error' IS NOT NULL") }

  def failed?
    payload.is_a?(Hash) && payload["error"].present?
  end

  def increment_retry!
    update!(retry_attempts: retry_attempts + 1)
  end
end


# # app/models/api/api_webhook_event.rb
# module Api
#   class ApiWebhookEvent < ApplicationRecord
#     self.table_name = "api_webhook_events"

#     belongs_to :partner

#     # === Validations ===
#     validates :event_type, presence: true
#     validates :bonid, presence: true
#     validates :retry_attempts, numericality: { greater_than_or_equal_to: 0 }

#     # === Scopes ===
#     scope :recent, -> { order(created_at: :desc) }
#     scope :failed, -> { where("payload ->> 'error' IS NOT NULL") }

#     # === Utility ===
#     def failed?
#       payload.is_a?(Hash) && payload["error"].present?
#     end

#     def increment_retry!
#       update!(retry_attempts: retry_attempts + 1)
#     end
#   end
# end
