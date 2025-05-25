class AddPostalCodeToCommunes < ActiveRecord::Migration[8.0]
  def change
    add_column :communes, :postal_code, :string
  end
end
