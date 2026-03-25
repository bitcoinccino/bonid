# db/migrate/XXXXXXXXXXXX_change_consent_grants_status_to_integer.rb
class ChangeConsentGrantsStatusToInteger < ActiveRecord::Migration[8.0]
  def up
    add_column :consent_grants, :status_tmp, :integer, default: 0, null: false

    say_with_time "Migrating consent_grant.status text to integer enum" do
      ConsentGrant.reset_column_information
      ConsentGrant.find_each do |grant|
        map = { "pending" => 0, "approved" => 1, "revoked" => 2, "expired" => 3 }
        grant.update_column(:status_tmp, map[grant.status] || 0)
      end
    end

    remove_column :consent_grants, :status
    rename_column :consent_grants, :status_tmp, :status
  end

  def down
    add_column :consent_grants, :status_tmp, :string, default: "pending"

    say_with_time "Reverting consent_grant.status integer to text" do
      ConsentGrant.reset_column_information
      ConsentGrant.find_each do |grant|
        map = %w[pending approved revoked expired]
        grant.update_column(:status_tmp, map[grant.status] || "pending")
      end
    end

    remove_column :consent_grants, :status
    rename_column :consent_grants, :status_tmp, :status
  end
end
