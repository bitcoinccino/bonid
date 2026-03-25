module Admin
  class PartnerAccessLogsController < Admin::BaseController
    require "csv"

    def index
      # === Base Scope ===
      @logs = PartnerAccessLog.includes(:partner, :admin_user).order(created_at: :desc)

      # === Filters ===
      if params[:partner_id].present?
        @logs = @logs.where(partner_id: params[:partner_id])
      end

      if params[:sector].present?
        @logs = @logs.where("metadata ->> 'sector' = ?", params[:sector])
      end

      respond_to do |format|
        format.html do
          # === Pagination ===
          @logs = @logs.page(params[:page]).per(50)
        end
        format.csv do
          send_data generate_csv(@logs), filename: "partner_access_logs-#{Time.zone.today}.csv"
        end
      end
    end

    private

    def generate_csv(logs)
      CSV.generate(headers: true) do |csv|
        csv << [ "ID", "Partner", "Admin User", "Sector", "Action", "Metadata", "Created At" ]

        logs.find_each do |log|
          csv << [
            log.id,
            log.partner&.name,
            log.admin_user&.email,
            log.metadata["sector"],
            log.action,
            log.metadata.to_json,
            log.created_at.strftime("%Y-%m-%d %H:%M")
          ]
        end
      end
    end
  end
end
