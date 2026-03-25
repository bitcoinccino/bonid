# frozen_string_literal: true

module Officers
  class OnboardingController < ApplicationController
    layout "officer_auth"

    before_action :authenticate_officer!
    before_action :redirect_if_already_onboarded

    def new
      # current_officer is now an Officer record
      @officer = current_officer
      @officer.build_address if @officer.address.blank?
    end

    def create
      @officer = current_officer

      # Update the existing Officer record with real data
      @officer.assign_attributes(officer_params)
      @officer.approved = true
      @officer.approved_at = Time.current
      @officer.status = :active

      if @officer.save
        flash[:notice] = "Welcome to the BonID Officer Portal! Your profile has been set up successfully."
        redirect_to officers_dashboard_path
      else
        @officer.build_address if @officer.address.blank?
        flash.now[:alert] = "Please fix the errors below to complete your profile."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def officer_params
      params.require(:officer).permit(
        :badge_id, :rank, :unit_name, :unit_type,
        :first_name, :last_name, :phone_number,
        address_attributes: [
          :department_id, :arrondissement_id, :commune_id,
          :communal_section_id, :postal_code, :street_address, :locality
        ]
      )
    end

    def redirect_if_already_onboarded
      # If officer has completed onboarding (has real badge_id, not placeholder)
      if current_officer.is_a?(Officer) && !current_officer.badge_id.to_s.start_with?("PENDING-")
        redirect_to officers_dashboard_path
      end
    end
  end
end
