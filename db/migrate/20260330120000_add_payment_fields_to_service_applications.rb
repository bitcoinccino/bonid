class AddPaymentFieldsToServiceApplications < ActiveRecord::Migration[7.1]
  def change
    add_column :service_applications, :payment_method, :string
    add_column :service_applications, :payment_token, :string
    add_column :service_applications, :payment_transaction_id, :string
    add_index :service_applications, :payment_token, unique: true, where: "payment_token IS NOT NULL"
  end
end
