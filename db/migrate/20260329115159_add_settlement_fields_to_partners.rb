class AddSettlementFieldsToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :settlement_cashtag, :string
    add_column :partners, :settlement_method, :string
    add_column :partners, :settlement_bank_details, :jsonb
  end
end
