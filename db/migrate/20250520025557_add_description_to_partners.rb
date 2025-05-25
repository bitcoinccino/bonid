class AddDescriptionToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :description, :text
  end
end
