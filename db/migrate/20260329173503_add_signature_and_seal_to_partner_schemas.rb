class AddSignatureAndSealToPartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_schemas, :requires_signature, :boolean, default: false
    add_column :partner_schemas, :auto_stamp, :boolean, default: false
  end
end
