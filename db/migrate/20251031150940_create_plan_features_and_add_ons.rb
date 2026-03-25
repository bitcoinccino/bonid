class CreatePlanFeaturesAndAddOns < ActiveRecord::Migration[7.1]
  def change
    create_table :plan_features do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :included, default: false, null: false
      t.references :partner_plan, null: false, foreign_key: true

      t.timestamps
    end

    create_table :plan_add_ons do |t|
      t.string :name, null: false
      t.integer :price_cents, null: false, default: 0
      t.string :unit
      t.references :partner_plan, null: false, foreign_key: true

      t.timestamps
    end
  end
end
