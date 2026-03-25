class AddPhysicalTraitsToPhysicalProfiles < ActiveRecord::Migration[7.1]
  def change
    # Add missing fields safely
    add_column :physical_profiles, :hair_style, :string unless column_exists?(:physical_profiles, :hair_style)
    add_column :physical_profiles, :tattoos, :text unless column_exists?(:physical_profiles, :tattoos)
    add_column :physical_profiles, :scars, :text unless column_exists?(:physical_profiles, :scars)
  end
end
