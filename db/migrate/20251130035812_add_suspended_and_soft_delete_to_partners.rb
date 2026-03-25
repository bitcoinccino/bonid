class AddSuspendedAndSoftDeleteToPartners < ActiveRecord::Migration[8.0]
  def change
    # Soft deletion
    unless column_exists?(:partners, :deleted_at)
      add_column :partners, :deleted_at, :datetime
      add_column :partners, :deleted_by_admin_id, :integer
      add_column :partners, :deleted_reason, :text
      add_index  :partners, :deleted_at
    end

    # Suspension
    unless column_exists?(:partners, :suspended_at)
      add_column :partners, :suspended_at, :datetime
      add_column :partners, :suspended_by_admin_id, :integer
      add_column :partners, :suspended_reason, :text
      add_index  :partners, :suspended_at
    end
  end
end
