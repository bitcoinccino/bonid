class MigrateUserSocialHandleToSocialHandles < ActiveRecord::Migration[7.1]
  def up
    User.reset_column_information
    User.find_each do |user|
      if user.social_handle.present?
        SocialHandle.create!(
          user_id: user.id,
          platform: "general",   # default since old field didn’t track platform
          handle: user.social_handle,
          active: true,
          since: Date.today - 5.years # assumption, adjust if you want nil
        )
      end
    end
  end

  def down
    # optional: move data back into users.social_handle
    SocialHandle.find_each do |sh|
      user = sh.user
      user.update!(social_handle: sh.handle) if user.social_handle.blank?
    end
  end
end
