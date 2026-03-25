module Admin
  class ApiUsageController < Admin::BaseController
    helper Admin::ApiUsageHelper

    def index
      # --- Filter params ---
      @partner_id = params[:partner_id]
      @status     = params[:status]
      @endpoint   = params[:endpoint]
      @from       = params[:from]
      @to         = params[:to]

      # --- Base scope ---
      logs_scope = PartnerApiLog.includes(:partner).order(requested_at: :desc)

      # --- Apply filters ---
      logs_scope = logs_scope.where(partner_id: @partner_id) if @partner_id.present?
      logs_scope = logs_scope.where(log_status: @status) if @status.present?
      logs_scope = logs_scope.where("endpoint ILIKE ?", "%#{@endpoint}%") if @endpoint.present?
      logs_scope = logs_scope.where("requested_at >= ?", @from.to_date.beginning_of_day) if @from.present?
      logs_scope = logs_scope.where("requested_at <= ?", @to.to_date.end_of_day) if @to.present?

      # --- Pagination ---
      @logs = logs_scope.page(params[:page]).per(50)

      # --- Dropdown options ---
      @partner_options = Partner.order(:name)
      @status_options  = PartnerApiLog.log_statuses.keys.map { |s| [ s.titleize, s ] }

      # --- Metrics ---
      grouped_scope = logs_scope.unscope(:includes, :order) # Remove includes/order for PG-safe grouping

      @metrics = {
        total_requests: logs_scope.count,
        success_rate: calculate_success_rate(logs_scope),
        top_endpoints: grouped_scope.group(:endpoint)
                                    .order(Arel.sql("COUNT(*) DESC"))
                                    .limit(5)
                                    .count,
        requests_by_status: grouped_scope.group(:log_status).count
      }

      # --- Respond ---
      respond_to do |format|
        format.html
        format.csv { send_data export_csv(logs_scope), filename: "partner_api_logs_#{Time.current.strftime('%Y%m%d_%H%M')}.csv" }
      end
    end

    private

    def calculate_success_rate(logs)
      return 0 if logs.count.zero?
      ((logs.where(log_status: :success).count.to_f / logs.count) * 100).round(2)
    end

    def export_csv(logs)
      CSV.generate(headers: true) do |csv|
        csv << [ "Timestamp", "Partner", "Endpoint", "Method", "Status Code", "Status", "Response Time (ms)", "IP", "User Agent" ]
        logs.find_each do |log|
          csv << [
            log.requested_at.strftime("%Y-%m-%d %H:%M:%S"),
            log.partner&.name,
            log.endpoint,
            log.request_method,
            log.status_code,
            log.log_status,
            log.response_time_ms,
            log.ip_address,
            log.user_agent
          ]
        end
      end
    end
  end
end
