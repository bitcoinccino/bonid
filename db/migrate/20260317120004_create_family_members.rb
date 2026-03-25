# frozen_string_literal: true

class CreateFamilyMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :family_members do |t|
      # The citizen this family member belongs to
      t.references :user, null: false, foreign_key: true, index: true

      # Relationship type
      t.integer :relationship, null: false, default: 0  # enum: mother, father, guardian, legal_representative

      # Identity fields
      t.string :first_name, null: false
      t.string :middle_name
      t.string :last_name, null: false
      t.date :date_of_birth
      t.string :place_of_birth
      t.string :nationality, default: "Haitian"
      t.boolean :alive, default: true, null: false

      # Linked BonID — if the family member is also a registered BonID citizen
      t.bigint :linked_user_id
      t.string :linked_bonid          # cached BonID string for display
      t.datetime :link_confirmed_at   # null until the linked person approves

      # Consent tracking — the linked person must approve the link
      t.string :link_consent_token    # sent to linked person for approval
      t.datetime :link_consent_sent_at

      # Audit
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    # FK to users for linked BonID (nullable)
    add_foreign_key :family_members, :users, column: :linked_user_id, on_delete: :nullify

    # A citizen can only have one mother, one father (but multiple guardians)
    add_index :family_members, [:user_id, :relationship],
              unique: true,
              where: "relationship IN (0, 1)",  # mother=0, father=1
              name: "idx_family_one_mother_one_father"

    # Fast lookup: "who lists me as their parent?"
    add_index :family_members, :linked_user_id, where: "linked_user_id IS NOT NULL",
              name: "idx_family_linked_user"

    add_index :family_members, :link_consent_token, unique: true,
              where: "link_consent_token IS NOT NULL",
              name: "idx_family_link_consent_token"
  end
end
