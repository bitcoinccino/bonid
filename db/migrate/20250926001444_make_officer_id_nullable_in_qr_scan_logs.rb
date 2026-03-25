class MakeOfficerIdNullableInQrScanLogs < ActiveRecord::Migration[7.1]
  def change
    change_column_null :qr_scan_logs, :officer_id, true
  end
end
