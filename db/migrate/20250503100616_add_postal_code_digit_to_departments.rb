class AddPostalCodeDigitToDepartments < ActiveRecord::Migration[8.0]
  def change
    add_column :departments, :postal_code_digit, :string
  end
end
