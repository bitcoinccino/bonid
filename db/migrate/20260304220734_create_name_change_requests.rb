class CreateNameChangeRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :name_change_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :admin_users }

      # Old name (snapshot at request time)
      t.string :old_first_name, null: false
      t.string :old_middle_name
      t.string :old_last_name, null: false

      # Requested new name
      t.string :new_first_name, null: false
      t.string :new_middle_name
      t.string :new_last_name, null: false

      # Workflow
      t.integer :status, default: 0, null: false # 0=pending, 1=approved, 2=rejected
      t.string  :reason, null: false              # marriage, court_order, error, other
      t.text    :other_reason
      t.text    :rejection_reason
      t.text    :admin_note

      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :name_change_requests, :status
  end
end
