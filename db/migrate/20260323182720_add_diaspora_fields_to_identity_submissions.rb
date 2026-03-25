class AddDiasporaFieldsToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :country_of_residence, :string, default: "HT"
    add_column :identity_submissions, :host_country_id_type, :string
  end
end
