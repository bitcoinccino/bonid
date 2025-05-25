# app/controllers/admin/qr_scans_controller.rb
module Admin
  class Admin::QrScanLogsController < Admin::ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin!

    # app/controllers/admin/qr_scans_controller.rb
    def index
      @qr_scans = QrScan.includes(:partner, identity_submission: :user).order(created_at: :desc)
    end


    private

    def ensure_admin!
      redirect_to root_path, alert: "Access denied" unless current_user&.admin?
    end
  end
end
