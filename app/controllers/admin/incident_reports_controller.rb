module Admin
  class IncidentReportsController < Admin::ApplicationController
    before_action :set_incident_report, only: [ :show, :approve, :flag, :scan_result ]

    # GET /admin/incident_reports
    def index
      @q = IncidentReport.includes(:officer, :address, :media_attachments).ransack(params[:q])
      @incident_reports = @q.result.order(created_at: :desc).page(params[:page])

      respond_to do |format|
        format.html
        format.csv do
          send_data @incident_reports.to_csv,
                    filename: "incident-reports-#{Date.today}.csv"
        end
      end
    end

    # GET /admin/incident_reports/:id
    def show
      respond_to do |format|
        format.html
        format.pdf do
          render pdf: "incident_report_#{@incident_report.id}",
                 layout: "pdf",
                 template: "admin/incident_reports/show",
                 show_as_html: params[:debug].present?
        end
      end
    end

    # PATCH /admin/incident_reports/:id/approve
    def approve
      @incident_report.update(status: :approved, reviewed_by: current_admin_user)
      redirect_to admin_incident_report_path(@incident_report),
                  notice: "Incident approved."
    end

    # PATCH /admin/incident_reports/:id/flag
    def flag
      @incident_report.update(
        status: :flagged,
        reviewed_by: current_admin_user,
        review_comment: params[:review_comment]
      )
      redirect_to admin_incident_report_path(@incident_report),
                  alert: "Incident flagged."
    end

    # POST /admin/incident_reports/scan_result
    def scan_result
      if params[:bonid].present?
        handle_bonid_scan(params[:bonid])
      elsif @incident_report
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "qr_scanner_result",
              partial: "admin/incident_reports/scan_result",
              locals: { incident_report: @incident_report }
            )
          end
          format.html { render :scan_result }
        end
      else
        invalid_request
      end
    end

    private

    def set_incident_report
      # Find by UUID for security (prevents enumeration attacks)
      @incident_report = IncidentReport.find_by(uuid: params[:id])
      unless @incident_report
        redirect_to admin_incident_reports_path, alert: "Incident report not found."
      end
    end

    def handle_bonid_scan(bonid)
      @bonid = bonid
      @submission = IdentitySubmission.approved.find_by(bonid: @bonid)

      if @submission&.verified?
        @user = @submission.user
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "bonidScanResult",
              partial: "admin/incident_reports/scan_result_valid",
              locals: {
                submission: @submission,
                user: @user,
                redirect_to: new_admin_officers_incident_report_path(bonid_submission_id: @submission.id)
              }
            )
          end
          format.html { render :scan_result_valid }
        end
      else
        flash.now[:alert] = "No record found for BonID #{@bonid}. This BonID may be invalid, revoked, or forged."
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "bonidScanResult",
              partial: "admin/incident_reports/scan_result_invalid",
              locals: { bonid: @bonid, status: :not_found, redirect_to: nil }
            )
          end
          format.html { render :scan_result_invalid }
        end
      end
    end

    def invalid_request
      flash.now[:alert] = "Invalid request: missing BonID or incident report ID."
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "bonidScanResult",
            partial: "admin/incident_reports/scan_result_invalid",
            locals: { bonid: nil, status: :invalid_request, redirect_to: nil }
          )
        end
        format.html { render :scan_result_invalid }
      end
    end
  end
end
