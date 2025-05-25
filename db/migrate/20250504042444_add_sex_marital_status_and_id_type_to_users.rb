class AddSexMaritalStatusAndIdTypeToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :sex, :integer
    add_column :users, :marital_status, :integer
    add_column :users, :id_type, :integer
  end
end
