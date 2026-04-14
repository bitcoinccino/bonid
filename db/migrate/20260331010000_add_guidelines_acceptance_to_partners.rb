# frozen_string_literal: true

class AddGuidelinesAcceptanceToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :guidelines_accepted_at, :datetime
    add_column :partners, :guidelines_version, :string
    add_column :partners, :guidelines_accepted_by_id, :bigint

    add_index :partners, :guidelines_accepted_at
  end
end
