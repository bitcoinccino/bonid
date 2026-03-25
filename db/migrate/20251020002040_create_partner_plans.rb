class CreatePartnerPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :partner_plans do |t|
      t.string :name
      t.string :slug
      t.text :description
      t.decimal :price
      t.string :billing_cycle
      t.integer :max_verifications
      t.integer :max_admins
      t.boolean :api_access
      t.boolean :custom_domain
      t.boolean :priority_support
      t.boolean :active

      t.timestamps
    end
  end
end
