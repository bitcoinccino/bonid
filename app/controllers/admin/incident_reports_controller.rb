# app/controllers/admin/incident_reports_controller.rb
module Admin
  class IncidentReportsController < Admin::ApplicationController
    before_action :authenticate_admin!
    before_action :set_incident_report, only: [:show, :approve, :flag]

    def index
      @q = IncidentReport.includes(:officer, :address, :media_attachments).ransack(params[:q])
      @incident_reports = @q.result.order(created_at: :desc).page(params[:page])
  
      respond_to do |format|
        format.html
        format.csv { send_data @incident_reports.to_csv, filename: "incident-reports-#{Date.today}.csv" }
      end
    end

    def show
      @incident_report = IncidentReport.find(params[:id])
    
      respond_to do |format|
        format.html
        format.pdf do
          render pdf: "incident_report_#{@incident_report.id}",
                 layout: "pdf", # uses app/views/layouts/pdf.html.erb
                 template: "admin/incident_reports/show", # standard view template
                 show_as_html: params[:debug].present? # helpful for debugging
        end
      end
    end

    private

    def authenticate_admin!
      redirect_to root_path, alert: "Access denied." unless current_user&.admin?
    end

    def approve
      report = IncidentReport.find(params[:id])
      report.update(status: :approved, reviewed_by: current_user)
      redirect_to admin_incident_report_path(report), notice: "Incident approved."
    end
    
    def flag
      report = IncidentReport.find(params[:id])
      report.update(
        status: :flagged,
        reviewed_by: current_user,
        review_comment: params[:review_comment]
      )
      redirect_to admin_incident_report_path(report), alert: "Incident flagged."
    end
    
  end
end
