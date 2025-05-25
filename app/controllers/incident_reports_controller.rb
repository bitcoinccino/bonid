# app/controllers/officers/incident_reports_controller.rb
class IncidentReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_officer
  before_action :set_incident_report, only: [:show, :edit, :update]

  def index
    @incident_reports = current_user.officer.incident_reports.order(created_at: :desc)
  end

  def new_incident_report
    @incident_report = current_user.officer.incident_reports.build
    @incident_report.build_address unless @incident_report.address.present?
    @departments = Department.order(:name)
  end

  def create
    @incident_report = current_user.officer.incident_reports.build(incident_report_params)
    if @incident_report.save
      redirect_to incident_reports_path, notice: "Incident report submitted successfully."
    else
      @departments = Department.order(:name)
      rrender :new, status: :unprocessable_entity

    end
  end

  def show
  end

  def edit
    redirect_to officer_dashboard_path, alert: "Unauthorized" unless @incident_report.officer == current_user.officer
  end

  def update
    if @incident_report.update(incident_report_params)
      redirect_to officer_dashboard_path, notice: "Incident updated successfully."
    else
      flash.now[:alert] = "Please correct the errors."
      render :edit
    end
  end

#    
  def bonid_lookup
    user = User.find_by(bonid: params[:bonid])
    
    if user
      render json: {
        name: "#{user.first_name} #{user.middle_name&.first&.upcase}. #{user.last_name}",
        dob: user.dob,
        id_number: user.id_number,
        status: "found"
      }
    else
      render json: { status: "not_found" }, status: :not_found
    end
  end
  

  private

  def set_incident_report
    @incident_report = current_user.officer.incident_reports.find(params[:id])
  end

  def require_officer
    redirect_to root_path, alert: "Access denied" unless current_user&.officer?
  end

  def incident_report_params
    params.require(:incident_report).permit(
      :crime_type, :description, :occurred_at, :suspect_user_id,
      media: [],
      address_attributes: [
        :street_address, :postal_code, :commune_id, :communal_section_id, :arrondissement_id, :department_id, :locality, :latitude, :longitude
      ]
    )
  end
end
