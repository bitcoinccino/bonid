class CreateReviewerActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :reviewer_activities do |t|
      t.references :user,   null: false, foreign_key: true, index: true
      t.string     :action,  null: false  # login, view_submission, approve, reject, override_warning
      t.string     :target_type             # polymorphic (e.g. "IdentitySubmission")
      t.bigint     :target_id               # polymorphic ID
      t.jsonb      :metadata, default: {}   # IP, time_spent, warnings_ignored, rejection_reason, etc.
      t.string     :ip_address
      t.timestamps
    end

    add_index :reviewer_activities, :action
    add_index :reviewer_activities, [:target_type, :target_id]
    add_index :reviewer_activities, :created_at
  end
end
