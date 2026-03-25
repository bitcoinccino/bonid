class AddHmacSignatureValueToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :hmac_signature_value, :string
  end
end
