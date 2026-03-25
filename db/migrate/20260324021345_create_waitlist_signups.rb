class CreateWaitlistSignups < ActiveRecord::Migration[8.0]
  def change
    create_table :waitlist_signups do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :signup_type, default: "citizen"  # citizen, business
      t.references :commune, null: true, foreign_key: true
      t.string :sector                            # for business signups
      t.string :referral_code                     # auto-generated for viral sharing
      t.string :invite_code_used                  # which invite code they used (if any)
      t.boolean :diaspora, default: false
      t.string :country_of_residence
      t.string :organization_name                 # for business signups
      t.string :status, default: "waiting"        # waiting, invited, converted
      t.datetime :invited_at                      # when they got the launch email
      t.datetime :converted_at                    # when they created a real account

      t.timestamps
    end
    add_index :waitlist_signups, :email, unique: true
    add_index :waitlist_signups, :referral_code, unique: true
    add_index :waitlist_signups, :status
    add_index :waitlist_signups, :signup_type
  end
end
