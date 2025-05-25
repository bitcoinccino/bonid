class PartnerApplicationsController < ApplicationController
  before_action :set_partner_application, only: [:show, :edit, :update]
  def index
    @partners = Partner.where.not(verified_at: nil)

    if params[:search].present?
      @partners = @partners.where("name ILIKE ?", "%#{params[:search]}%")
    end

    if params[:sector].present?
      @partners = @partners.where(sector: params[:sector])
    end

    @partners = @partners.order(:name)
  end

  def show
    @application = PartnerApplication.find(params[:id])
    @partner = @application.partner # optional
  end
  

  def new
    @partner_application = PartnerApplication.new
    @partner_application.build_address
  end

  def create
    @partner_application = PartnerApplication.new(partner_application_params)

    if @partner_application.save
      if @partner_application.law_enforcement_sector?
        redirect_to partners_path, notice: "Thank you! We'll be in touch soon."
      else
        redirect_to partners_path, notice: "Application submitted for review."
      end
    else
      Rails.logger.debug "🚨 PartnerApplication errors: #{@partner_application.errors.full_messages}"
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    # @partner_application is already set by the before_action
    @partner_application.build_address if @partner_application.address.blank?
  end

  def update
    if @partner_application.update(partner_application_params)
      redirect_to admin_partner_application_path(@partner_application), notice: "Application updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
  

  private

  def partner_application_params
    params.require(:partner_application).permit(
      :logo,
      :organization_name,
      :website,
      :contact_person,
      :email,
      :phone_number,
      :sector,
      :contact_code,
      :description,
      :slug,
      :verified_at,
      :department_sector,
      :unit_name,
      :unit_type,  # ✅ ADD THIS
      use_cases: [],
      address_attributes: [
        :street_address,
        :locality,
        :postal_code,
        :department_id,
        :arrondissement_id,
        :commune_id,
        :communal_section_id,
        :country
      ]
    )
  end

  def honeypot_detected?(application)
    application.contact_code.present?
  end
  
end

