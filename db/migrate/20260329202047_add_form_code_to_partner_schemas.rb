class AddFormCodeToPartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_schemas, :form_code, :string
    add_column :partner_schemas, :form_revision, :string
    add_index :partner_schemas, :form_code
  end
end
