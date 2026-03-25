class AddIndexToSignatureHashInIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    unless index_exists?(:identity_submissions, :signature_hash)
      add_index :identity_submissions, :signature_hash
    end
  end
end
