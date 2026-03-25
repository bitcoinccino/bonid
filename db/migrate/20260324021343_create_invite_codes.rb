class CreateInviteCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :invite_codes do |t|
      t.string :code, null: false
      t.string :code_type, default: "personal"  # personal, partner, community, unlimited, referral
      t.integer :max_uses, default: 1
      t.integer :uses_count, default: 0
      t.references :partner, null: true, foreign_key: true
      t.references :commune, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true  # who created it (for referrals)
      t.datetime :expires_at
      t.boolean :active, default: true, null: false
      t.string :note  # internal note, e.g. "For Zellus beta testers"

      t.timestamps
    end
    add_index :invite_codes, :code, unique: true
    add_index :invite_codes, :code_type
  end
end
