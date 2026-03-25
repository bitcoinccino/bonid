class MakeUserIdNullableInApiAccessLogs < ActiveRecord::Migration[8.0]
  def change
    change_column_null :api_access_logs, :user_id, true
  end
end
