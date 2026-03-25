class AddHmacSignatureToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :hmac_signature, :string
  end
end
