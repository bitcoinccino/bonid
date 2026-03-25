class AddCertificateSignatureToOfficerComplaints < ActiveRecord::Migration[8.0]
  def change
    add_column :officer_complaints, :certificate_signature, :string
    add_column :officer_complaints, :certificate_signed_at, :datetime
  end
end
