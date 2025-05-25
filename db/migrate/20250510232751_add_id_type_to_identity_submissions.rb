class AddIdTypeToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :id_type, :string
  end
end
