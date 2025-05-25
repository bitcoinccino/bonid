class AddInvitationTokenToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :invitation_token, :string
  end
end
