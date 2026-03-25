# app/controllers/admin/qr_scans_controller.rb
module Admin
  class QrScansController < Admin::ApplicationController
    before_action :authenticate_admin_user!

    def index
      @qr_scans = QrScan.includes(:partner, identity_submission: :user)
                        .order(created_at: :desc)

      # Optional filters
      if params[:partner_id].present?
        @qr_scans = @qr_scans.where(partner_id: params[:partner_id])
      end

      if params[:search].present?
        term = "%#{params[:search]}%"
        @qr_scans = @qr_scans.joins(identity_submission: :user)
                             .left_joins(:partner)
                             .where("users.full_name ILIKE ? OR partners.name ILIKE ?", term, term)
      end

      if params[:date_range].present?
        start_date, end_date = params[:date_range].split(" - ").map(&:to_date)
        @qr_scans = @qr_scans.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
      end

      respond_to do |format|
        format.html { @qr_scans = @qr_scans.page(params[:page]).per(20) }
        format.csv { send_data @qr_scans.to_csv, filename: "qr_scans-#{Date.today}.csv" }
      end
    end
  end
end
