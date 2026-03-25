# frozen_string_literal: true

class AddIndexBonidToUsers < ActiveRecord::Migration[7.1]
  def up
    # Cleanup: nullify duplicate bonids (keep the newest row per bonid)
    execute <<~SQL
      UPDATE users SET bonid = NULL
      WHERE id NOT IN (
        SELECT MAX(id) FROM users WHERE bonid IS NOT NULL GROUP BY bonid
      ) AND bonid IS NOT NULL
    SQL

    # Partial unique index — users without a bonid yet don't conflict
    add_index :users, :bonid, unique: true, where: "bonid IS NOT NULL", name: "index_users_on_bonid_unique"

    # Compound index for verified_identity_submission lookups: user.identity_submissions.find_by(status: :approved)
    add_index :identity_submissions, [:user_id, :status], name: "idx_identity_submissions_user_status"
  end

  def down
    remove_index :users, name: "index_users_on_bonid_unique"
    remove_index :identity_submissions, name: "idx_identity_submissions_user_status"
  end
end
