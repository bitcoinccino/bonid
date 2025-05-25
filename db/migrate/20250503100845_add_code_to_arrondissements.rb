class AddCodeToArrondissements < ActiveRecord::Migration[8.0]
  def change
    add_column :arrondissements, :code, :string
  end
end
