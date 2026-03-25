# db/migrate/XXXXXXXXXXXXXX_add_ninu_to_identity_submissions.rb
class AddNinuToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :ninu, :string, limit: 10
    add_index  :identity_submissions, :ninu
  end
end
