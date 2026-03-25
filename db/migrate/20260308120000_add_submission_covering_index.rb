class AddSubmissionCoveringIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Covering index for the hot query: user.identity_submissions.where(status:).order(created_at: :desc)
    # Replaces the 2-column [:user_id, :status] index with a 3-column version.
    remove_index :identity_submissions, [:user_id, :status], algorithm: :concurrently, if_exists: true
    add_index :identity_submissions, [:user_id, :status, :created_at],
              name: "idx_submissions_user_status_recent",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
