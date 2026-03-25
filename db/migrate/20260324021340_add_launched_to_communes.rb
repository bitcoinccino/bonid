class AddLaunchedToCommunes < ActiveRecord::Migration[8.0]
  def change
    add_column :communes, :launched, :boolean, default: false, null: false
  end
end
