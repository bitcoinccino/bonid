class AddOtherFieldsToHealthProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :health_profiles, :allergies_other, :string
    add_column :health_profiles, :chronic_conditions_other, :string
    add_column :health_profiles, :medications_other, :string
  end
end
