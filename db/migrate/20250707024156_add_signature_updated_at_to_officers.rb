class AddSignatureUpdatedAtToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :signature_updated_at, :datetime
  end
end
