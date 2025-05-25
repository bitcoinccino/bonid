class AddPartnerToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_reference :identity_submissions, :partner, null: false, foreign_key: true
  end
end
