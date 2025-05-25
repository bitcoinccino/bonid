class AddPhoneNumberToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :phone_number, :string
  end
end
