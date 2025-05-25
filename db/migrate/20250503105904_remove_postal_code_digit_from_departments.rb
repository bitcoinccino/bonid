class RemovePostalCodeDigitFromDepartments < ActiveRecord::Migration[7.1]
  def change
    remove_column :departments, :postal_code_digit, :string
  end
end