class CreatePartnerApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :partner_applications do |t|
      t.string :organization_name
      t.string :contact_person
      t.string :email
      t.string :phone_number
      t.string :department_sector
      t.string :website
      t.string :human_token
      t.string :use_cases, array: true, default: [], null: false

      t.timestamps
    end
  end
end
