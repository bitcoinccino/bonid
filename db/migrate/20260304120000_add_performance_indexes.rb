class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Identity submissions — frequently filtered/grouped by status
    add_index :identity_submissions, :status, algorithm: :concurrently, if_not_exists: true
    add_index :identity_submissions, [:user_id, :status], algorithm: :concurrently, if_not_exists: true
    add_index :identity_submissions, :created_at, algorithm: :concurrently, if_not_exists: true

    # Users — dashboard demographics queries (group by sex, dob range)
    add_index :users, :sex, algorithm: :concurrently, if_not_exists: true
    add_index :users, :dob, algorithm: :concurrently, if_not_exists: true
  end
end
