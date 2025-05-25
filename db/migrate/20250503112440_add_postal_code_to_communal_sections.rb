class AddPostalCodeToCommunalSections < ActiveRecord::Migration[8.0]
  def change
    add_column :communal_sections, :postal_code, :string
  end
end
