# app/controllers/officers/incident_reports_controller.rb
module Officers
  class IncidentReportsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_officer!

    def new
      @incident_report = current_user.officer.incident_reports.build
    end

    def create
      @incident_report = current_user.officer.incident_reports.build(incident_report_params)
      if @incident_report.save
        redirect_to officer_dashboard_path, notice: "Incident report submitted successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @officer = Officer.find_by(invitation_token: params[:token])
      if @officer.nil? || @officer.invitation_accepted_at.present?
        redirect_to root_path, alert: "Invalid or expired invitation." and return
      end
    
      if @officer.update(officer_params.merge(invitation_accepted_at: Time.current, status: :active))
        redirect_to officer_dashboard_path, notice: "Welcome, your account has been activated."
      else
        flash.now[:alert] = "Please correct the errors below."
        render :accept_invitation
      end
    end

    def edit_profile
      @officer = current_officer
    end
  
    def update_profile
      @officer = current_officer
      if @officer.update(officer_profile_params)
        redirect_to officer_dashboard_path, notice: "Profile updated successfully."
      else
        flash.now[:alert] = "Please fix the errors below."
        render :edit_profile
      end
    end
     
    def bonid_lookup
      user = User.find_by(bonid: params[:bonid])
      if user && user.identity_submissions.approved.where("expires_at > ?", Time.current).exists?
        render json: { found: true, name: user.full_name, user_id: user.id }
      else
        render json: { found: false }
      end
    end
    

    private
    
    def officer_params
      params.require(:officer).permit(:full_name, :phone_number, :password, :password_confirmation)
    end

    def officer_profile_params
      params.require(:officer).permit(
        :full_name,
        :phone_number,
        :rank,
        :unit_name,
        :unit_type,
        :email,
        :avatar,
        :department_id,
        :arrondissement_id,
        :commune_id,
        :communal_section_id
      )
    end

    def incident_report_params
      params.require(:incident_report).permit(
        :crime_type,
        :description,
        :occurred_at,
        media: [],
        address_attributes: [
          :department_id,
          :arrondissement_id,
          :commune_id,
          :communal_section_id,
          :postal_code,
          :street_address,
          :locality,
          :latitude,
          :longitude
        ]
      )
    end
  end
end