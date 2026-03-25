# frozen_string_literal: true

class AddWebhookFieldsToPartners < ActiveRecord::Migration[7.1]
  def change
    add_column :partners, :webhook_url, :string
    add_column :partners, :webhook_secret, :string
  end
end
