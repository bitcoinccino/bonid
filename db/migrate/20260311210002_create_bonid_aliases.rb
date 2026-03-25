# frozen_string_literal: true

class CreateBonidAliases < ActiveRecord::Migration[7.1]
  def change
    create_table :bonid_aliases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :old_bonid, null: false
      t.string :new_bonid, null: false
      t.string :reason # "name_change", "resubmission", "manual_correction"
      t.datetime :created_at, null: false
    end

    add_index :bonid_aliases, :old_bonid, unique: true
    add_index :bonid_aliases, :new_bonid
  end
end
