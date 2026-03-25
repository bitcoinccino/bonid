class MoveBloodTypeFromUsersToHealthProfiles < ActiveRecord::Migration[7.1]
  def up
    User.find_each do |user|
      if user.blood_type.present?
        user.create_health_profile!(blood_type: user.blood_type)
      else
        user.create_health_profile!
      end
    end
    remove_column :users, :blood_type
  end

  def down
    add_column :users, :blood_type, :string
    HealthProfile.find_each do |hp|
      hp.user.update!(blood_type: hp.blood_type)
    end
  end
end
