# frozen_string_literal: true

class AddDeliveryFieldsToApiWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :api_webhook_events, :direction, :string, default: "outbound"
    add_column :api_webhook_events, :delivered_at, :datetime
    add_column :api_webhook_events, :status, :string, default: "pending"
    add_index  :api_webhook_events, :status
    add_index  :api_webhook_events, :event_type
  end
end
