# frozen_string_literal: true

module PartnerPortal
  class ProfileCompletionController < PartnerPortal::BaseController
    skip_before_action :ensure_profile_complete!
    skip_before_action :ensure_correct_sector
    layout "partner_portal/public"

    before_action :ensure_partner_exists
    before_action :check_if_profile_complete, only: [:index]

    # Show profile completion form
    def index
      @partner = @current_partner
      @partner.build_address unless @partner.address.present?
    end

    # Update profile with missing information
    def update
      @partner = @current_partner

      if @partner.update(profile_completion_params)
        # Mark profile as complete by setting a flag or checking completeness
        PartnerAuditLog.create!(
          partner: @partner,
          admin_user: nil,
          event: "profile_completed",
          details: "Partner completed their profile after approval"
        ) rescue nil

        redirect_to partner_portal_dashboard_path,
                    notice: "✅ Profile completed successfully! You can now access your dashboard."
      else
        @partner.build_address unless @partner.address.present?
        flash.now[:alert] = "⚠️ Please correct the errors below."
        render :index, status: :unprocessable_entity
      end
    end

    private

    def ensure_partner_exists
      unless @current_partner
        redirect_to root_path, alert: "No partner profile found."
      end
    end

    def check_if_profile_complete
      # If profile is already complete, redirect to dashboard
      if profile_complete?(@current_partner)
        redirect_to partner_portal_dashboard_path,
                    notice: "Your profile is already complete."
      end
    end

    def profile_complete?(partner)
      # Check if all required fields are present
      # Must match the check in BaseController
      return false unless partner.present?

      partner.description.present? &&
        partner.contact_person.present? &&
        partner.phone_number.present?
    end

    def profile_completion_params
      params.require(:partner).permit(
        # Contact info (most important)
        :contact_person,
        :phone_number,
        :website,

        # Organization details
        :description,
        :logo,

        # Unit info (law enforcement)
        :unit_type,
        :unit_name,
        :department_sector,

        # Address
        address_attributes: [
          :id, :street_address, :locality, :postal_code,
          :department_id, :arrondissement_id, :commune_id,
          :communal_section_id, :country
        ]
      )
    end
  end
end
