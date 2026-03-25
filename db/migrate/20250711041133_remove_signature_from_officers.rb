class RemoveSignatureFromOfficers < ActiveRecord::Migration[8.0]
  def change
    remove_column :officers, :signature_updated_at, :datetime
  end
end
