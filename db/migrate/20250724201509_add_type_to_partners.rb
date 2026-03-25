class AddTypeToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :type, :string
  end
end
