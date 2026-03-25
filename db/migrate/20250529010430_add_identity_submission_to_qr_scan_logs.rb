class AddIdentitySubmissionToQrScanLogs < ActiveRecord::Migration[8.0]
  def change
    add_reference :qr_scan_logs, :identity_submission, null: false, foreign_key: true
  end
end
