# frozen_string_literal: true

class AddCapacityToPartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_schemas, :capacity, :integer, null: true
  end
end
