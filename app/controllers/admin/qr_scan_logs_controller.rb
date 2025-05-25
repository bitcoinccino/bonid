# app/controllers/admin/qr_scan_logs_controller.rb
class Admin::QrScanLogsController < Admin::BaseController
  def index
      @qr_scan_logs = QrScanLog.includes(:partner, qr_scan: { identity_submission: :user }).order(created_at: :desc)
      @partners = Partner.all
  end
end

