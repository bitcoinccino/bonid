# frozen_string_literal: true

class CreateVisitorAccessGrants < ActiveRecord::Migration[7.1]
  def change
    create_table :visitor_access_grants do |t|
      t.references :visitor_submission, null: false, foreign_key: true

      t.string   :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :visitor_access_grants, :token, unique: true
  end
end
