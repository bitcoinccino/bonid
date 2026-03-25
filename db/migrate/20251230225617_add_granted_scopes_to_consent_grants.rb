class AddGrantedScopesToConsentGrants < ActiveRecord::Migration[7.1]  # or your Rails version
  def change
    add_column :consent_grants, :granted_scopes, :text, array: true, default: [], null: false
  end
end
