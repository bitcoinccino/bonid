class AddDeviseInvitableToOfficers < ActiveRecord::Migration[8.0]
  def change
    # Don't add invitation_token again — it already exists
    add_column :officers, :invitation_created_at, :datetime
    add_column :officers, :invitation_sent_at, :datetime
    add_column :officers, :invitation_limit, :integer
    add_column :officers, :invited_by_id, :bigint
    add_column :officers, :invited_by_type, :string
    add_column :officers, :invitations_count, :integer, default: 0

    add_index :officers, :invitation_token, unique: true unless index_exists?(:officers, :invitation_token)
    add_index :officers, [:invited_by_id, :invited_by_type] unless index_exists?(:officers, [:invited_by_id, :invited_by_type])
  end
end
