class AddLastAccessedToConsentGrants < ActiveRecord::Migration[8.0]
  def change
    add_column :consent_grants, :last_accessed_at, :datetime
    add_column :consent_grants, :access_count,     :integer, default: 0, null: false
    add_index  :consent_grants, :last_accessed_at
  end
end
