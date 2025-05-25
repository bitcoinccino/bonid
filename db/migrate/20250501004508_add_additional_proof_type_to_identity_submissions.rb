class AddAdditionalProofTypeToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :additional_proof_type, :string
  end
end
