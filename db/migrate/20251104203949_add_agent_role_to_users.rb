class AddAgentRoleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :agent_role, :string
    add_index :users, :agent_role
  end
end
