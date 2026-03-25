class AddMetadataToConsentGrants < ActiveRecord::Migration[8.0]
  def change
    # Only add missing fields — others already exist
    add_column :consent_grants, :requested_scopes, :string, array: true, default: [] unless column_exists?(:consent_grants, :requested_scopes)
    add_column :consent_grants, :requested_at, :datetime unless column_exists?(:consent_grants, :requested_at)
  end
end
