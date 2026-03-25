class RenameAgentRoleToAgentRankInUsers < ActiveRecord::Migration[8.0]
  def change
    rename_column :users, :agent_role, :agent_rank
  end
end
