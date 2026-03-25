class AddOnboardingFieldsToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :estimated_team_size, :string
    add_column :partners, :intended_users_to_verify, :integer
    add_column :partners, :preferred_integration, :string
    add_column :partners, :how_did_you_hear, :string
  end
end
