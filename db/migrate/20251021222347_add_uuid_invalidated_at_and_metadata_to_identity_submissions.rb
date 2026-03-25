class AddUuidInvalidatedAtAndMetadataToIdentitySubmissions < ActiveRecord::Migration[7.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    unless column_exists?(:identity_submissions, :uuid)
      add_column :identity_submissions, :uuid, :uuid, default: "gen_random_uuid()", null: false
    end

    unless column_exists?(:identity_submissions, :invalidated_at)
      add_column :identity_submissions, :invalidated_at, :datetime
    end

    unless column_exists?(:identity_submissions, :metadata)
      add_column :identity_submissions, :metadata, :jsonb, default: {}, null: false
    end
  end
end
