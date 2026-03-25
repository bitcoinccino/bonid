# frozen_string_literal: true

class AddDetailsToFamilyMembers < ActiveRecord::Migration[8.0]
  def change
    # Death date — shown when alive: false
    add_column :family_members, :date_of_death, :date

    # Guardian type — Tonton, Matant, Granmoun, etc.
    add_column :family_members, :guardian_type, :string

    # Place of birth as department/commune (structured, not freetext)
    add_reference :family_members, :birth_department, foreign_key: { to_table: :departments }, null: true
    add_reference :family_members, :birth_commune, foreign_key: { to_table: :communes }, null: true

    # Verification status for the relationship link
    add_column :family_members, :verification_status, :integer, default: 0, null: false
    # 0 = manual_entry, 1 = pending_confirmation, 2 = verified
  end
end
