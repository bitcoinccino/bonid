# app/controllers/admin/partner_applications_controller.rb
module Admin
  class PartnerApplicationsController < Admin::ApplicationController
    def index
      @applications = PartnerApplication.order(created_at: :desc)
    end

    
    def show
      @application = PartnerApplication.find_by(id: params[:id])
      @partner = @application&.partner
    end
    

    def edit
      @partner_application = PartnerApplication.find(params[:id])
      @partner_application.build_address unless @partner_application.address.present?
    end
    
    

    def update
      @partner_application = PartnerApplication.find(params[:id])

      if params[:approve]
        partner = Partner.find_or_initialize_by(email: @partner_application.email)

        partner.assign_attributes(
          name:           @partner_application.organization_name,
          contact_person: @partner_application.contact_person,
          sector:         @partner_application.department_sector,
          use_cases:      @partner_application.use_cases.reject(&:blank?),
          slug:           @partner_application.organization_name.parameterize,
          website:        @partner_application.website,
          verified_at:    Time.current
        )

        partner.save!

        # Create address if not already present
        if @partner_application.address.present? && partner.address.nil?
          partner.create_address(
            @partner_application.address.attributes.except(
              "id", "created_at", "updated_at", "addressable_id", "addressable_type"
            )
          )
          new_address.geocode
          new_address.save!
        end

        # Attach logo if not already present
        if @partner_application.logo.attached? && !partner.logo.attached?
          partner.logo.attach(@partner_application.logo.blob)
        end

        @partner_application.update!(approved: true, partner_id: partner.id)

        redirect_to admin_partner_applications_path, notice: "✅ Partner approved and created."
      elsif params[:reject]
        @partner_application.update!(rejection_reason: "Rejected manually")
        redirect_to admin_partner_applications_path, alert: "🚫 Partner application rejected."
      else
        redirect_to admin_partner_applications_path, alert: "⚠️ No action taken."
      end
    end
  end

  def geocode_address
    application = PartnerApplication.find(params[:id])
    address = application.address
  
    if address.present?
      address.geocode
      if address.save
        redirect_to admin_partner_application_path(application), notice: "📍 Address successfully geocoded."
      else
        redirect_to admin_partner_application_path(application), alert: "⚠️ Failed to save geocoded address."
      end
    else
      redirect_to admin_partner_application_path(application), alert: "❌ No address found to geocode."
    end
  end
  
end
