class RemoveSocialHandleFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :social_handle, :string
  end
end
