class AddPcodeToCommunalSections < ActiveRecord::Migration[8.0]
  def change
    add_column :communal_sections, :pcode, :string
  end
end
