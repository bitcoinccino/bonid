class AddProfileFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :first_name, :string
    add_column :users, :middle_name, :string
    add_column :users, :last_name, :string
    add_column :users, :dob, :date
    add_column :users, :phone, :string
    add_column :users, :social_handle, :string
    add_column :users, :street_address, :string
    add_column :users, :postal_code, :string
    add_column :users, :locality, :string
    add_column :users, :country, :string
    add_column :users, :place_of_birth, :string
    add_column :users, :nationality, :string
    add_column :users, :id_issued_on, :date
    add_column :users, :id_expires_on, :date
    add_column :users, :issuing_authority, :string
    add_column :users, :bonid, :string
  end
end
