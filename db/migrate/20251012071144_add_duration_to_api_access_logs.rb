class AddDurationToApiAccessLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :api_access_logs, :duration_ms, :float
  end
end
