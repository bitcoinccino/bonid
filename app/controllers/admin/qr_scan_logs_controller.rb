# app/controllers/admin/qr_scan_logs_controller.rb
module Admin
  class QrScanLogsController < Admin::ApplicationController
    before_action :authenticate_admin_user!

    helper_method :filter_params

    def index
      @partners = Partner.all

      @qr_scan_logs = QrScanLog
                        .includes(:partner, :officer, identity_submission: :user)
                        .order(scanned_at: :desc)

      # 🔍 Search
      if params[:search].present?
        term = "%#{params[:search].strip}%"
        @qr_scan_logs = @qr_scan_logs
                          .joins(identity_submission: :user)
                          .left_joins(:partner, :officer)
                          .where(
                            "users.full_name ILIKE :term OR users.email ILIKE :term OR partners.name ILIKE :term OR officers.full_name ILIKE :term OR officers.email ILIKE :term",
                            term: term
                          )
      end

      # 🎯 Partner filter
      if params[:partner_id].present?
        @qr_scan_logs = @qr_scan_logs.where(partner_id: params[:partner_id])
      end

      # 📅 Date range filter
      if params[:date_range].present?
        begin
          start_date, end_date = params[:date_range].split(" - ")
          start_date = Date.parse(start_date).beginning_of_day
          end_date   = Date.parse(end_date).end_of_day
          @qr_scan_logs = @qr_scan_logs.where(scanned_at: start_date..end_date)
        rescue ArgumentError
          flash.now[:alert] = "Invalid date range format"
        end
      end

      scoped_logs = @qr_scan_logs
      @qr_scan_logs = scoped_logs.page(params[:page]).per(20)

      respond_to do |format|
        format.html
        format.csv do
          send_data QrScanLog.to_csv(scoped_logs),
                    filename: "qr_scan_logs-#{Time.current.strftime("%Y%m%d")}.csv"
        end
        format.json { render json: @qr_scan_logs }
      end
    end

    private

    def filter_params
      params.slice(:search, :partner_id, :date_range).permit(:search, :partner_id, :date_range)
    end
  end
end
