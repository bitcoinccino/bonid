class AddInvitationAcceptedAtToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :invitation_accepted_at, :datetime
  end
end
