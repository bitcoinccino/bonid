class AddDiasporaProofTypeToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :diaspora_proof_type, :string
  end
end
