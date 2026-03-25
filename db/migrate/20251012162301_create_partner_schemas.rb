class CreatePartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    create_table :partner_schemas do |t|
      t.references :partner, null: false, foreign_key: true
      t.string :name
      t.string :record_type
      t.jsonb :structure
      t.jsonb :validation_rules
      t.string :visibility
      t.integer :version
      t.boolean :active
      t.datetime :approved_at

      t.timestamps
    end
  end
end
