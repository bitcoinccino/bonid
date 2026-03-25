class AddLogStatusToPartnerApiLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_api_logs, :log_status, :integer
  end
end
