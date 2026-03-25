class AddVisibilityAndVerificationToSocialHandles < ActiveRecord::Migration[8.0]
  def change
    add_column :social_handles, :visibility, :integer
    add_column :social_handles, :verification_status, :integer
    add_column :social_handles, :uid, :string
    add_column :social_handles, :access_token, :string
    add_column :social_handles, :refresh_token, :string
    add_column :social_handles, :expires_at, :datetime
  end
end
