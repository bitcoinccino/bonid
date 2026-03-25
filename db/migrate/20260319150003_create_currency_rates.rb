# frozen_string_literal: true

class CreateCurrencyRates < ActiveRecord::Migration[8.0]
  def change
    create_table :currency_rates do |t|
      t.string  :from_currency, null: false, default: "USD"
      t.string  :to_currency, null: false, default: "HTG"
      t.decimal :rate, precision: 12, scale: 4, null: false
      t.decimal :buffer_percentage, precision: 5, scale: 2, default: 5.0
      t.decimal :effective_rate, precision: 12, scale: 4
      t.string  :source, default: "manual"                  # "manual", "brh", "api"
      t.datetime :fetched_at
      t.timestamps
    end

    add_index :currency_rates, [:from_currency, :to_currency, :created_at],
              name: "idx_currency_rates_lookup"
  end
end
