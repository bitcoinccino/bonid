# app/controllers/partners_controller.rb
class PartnersController < ApplicationController
  layout "partner_portal/public"

  before_action :set_partner, only: %i[show edit update destroy approve reject]
  before_action :authenticate_admin!, only: %i[approve reject destroy edit update]

  def new
    @partner = Partner.new
    @partner.build_address
  end

  def create
    @partner = Partner.new(partner_params)

    # Detect if this is a PNH minimal signup (stored as "pnh" in department_sector)
    is_pnh_signup = @partner.department_sector == "pnh"

    if @partner.save
      audit_details =
        if is_pnh_signup
          "PNH minimal signup form submitted for #{@partner.name}"
        else
          "Full partner application submitted for #{@partner.name}"
        end

      PartnerAuditLog.create!(
        partner: @partner,
        event: "created",
        admin_user: nil,
        details: audit_details
      ) rescue nil

      Partners::Mailer.with(partner: @partner).confirmation_email.deliver_later

      success_message =
        if is_pnh_signup
          "✅ Your PNH application has been received. You'll receive an email once approved to complete your profile."
        else
          "✅ Your application has been received. Please check your email for confirmation."
        end

      redirect_to partners_path, notice: success_message
    else
      @is_pnh_signup = is_pnh_signup
      flash.now[:alert] = "⚠️ Please correct the errors below."
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_partner
    @partner = Partner.find_by(uuid: params[:uuid]) if params[:uuid].present?
  end

  def partner_params
    params.require(:partner).permit(
      :name,
      :contact_person,
      :email,
      :phone_number,
      :website,
      :sector,
      :department_sector,     # PNH minimal signup flow
      :unit_type,
      :unit_name,
      :use_cases,
      :other_use_case,
      :estimated_team_size,
      :intended_users_to_verify,
      :preferred_integration,
      :how_did_you_hear,
      :description,
      :logo,
      :country,

      # ✅ FIX: allow the checkbox from the form
      :terms_accepted,

      address_attributes: [
        :id, :street_address, :locality, :postal_code,
        :department_id, :arrondissement_id, :commune_id,
        :communal_section_id, :country
      ]
    )
  end
end



# # app/controllers/partners_controller.rb
# class PartnersController < ApplicationController
#   before_action :set_partner, only: [ :show, :edit, :update, :destroy, :approve, :reject ]
#   before_action :authenticate_admin!, only: [ :approve, :reject, :destroy, :edit, :update ]

#   # GET /partners
#   def index
#     @partners = Partner.where.not(verified_at: nil)
#     @partners = @partners.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
#     @partners = @partners.where(sector: params[:sector]) if params[:sector].present?
#     @partners = @partners.order(:name)
#   end

#   # GET /partners/:id
#   def show
#   end

#   # GET /partners/new
#   def new
#     @partner = Partner.new
#     @partner.build_address

#     # Prefill plan if coming from pricing page
#     if session[:selected_plan_id].present?
#       @partner.partner_plan = PartnerPlan.find_by(id: session[:selected_plan_id])
#     end
#   end

#   # POST /partners
#   def create
#     @partner = Partner.new(partner_params)

#     if @partner.save
#       PartnerAuditLog.create!(
#         partner: @partner,
#         event: "created",
#         admin_user: nil,
#         details: "Partner #{@partner.name} submitted minimal onboarding form."
#       ) rescue nil

#       redirect_to partners_path, notice: "✅ Your application has been received and is under review."
#     else
#       flash.now[:alert] = "⚠️ Please correct the errors below."
#       render :new, status: :unprocessable_entity
#     end
#   end

#   # GET /partners/:id/edit
#   def edit
#     @partner.build_address if @partner.address.blank?
#   end

#   # PATCH/PUT /partners/:id
#   def update
#     if @partner.update(partner_params)
#       redirect_to partner_path(@partner), notice: "Partner updated successfully."
#     else
#       flash.now[:alert] = "Error updating partner."
#       render :edit, status: :unprocessable_entity
#     end
#   end

#   # POST /partners/:id/approve
#   def approve
#     @partner.update!(verified_at: Time.current)
#     Partners::PartnerMailer.approved(@partner).deliver_later
#     redirect_to partners_path, notice: "Partner approved."
#   end

#   # POST /partners/:id/reject
#   def reject
#     @partner.update!(
#       rejection_reason: params[:partner][:rejection_reason],
#       rejection_comment: params[:partner][:rejection_comment]
#     )
#     Partners::PartnerMailer.rejected(@partner).deliver_later
#     redirect_to partners_path, notice: "Partner rejected."
#   end

#   # DELETE /partners/:id
#   def destroy
#     @partner.destroy
#     redirect_to partners_path, notice: "Partner deleted."
#   end

#   private

#   def set_partner
#     @partner = Partner.find(params[:id])
#   end


#   def partner_params
#     params.require(:partner).permit(
#       :name, :slug, :logo, :website, :email, :phone_number, :sector,
#       :description, :partner_plan_id, :unit_type, :unit_name,  # Add these
#       address_attributes: [
#         :id, :street_address, :locality, :postal_code, :department_id,
#         :arrondissement_id, :commune_id, :communal_section_id, :country
#       ]
#     )
#   end

#   def honeypot_detected?(partner)
#     partner.contact_code.present?
#   end

#   def verify_recaptcha
#     return true unless params["g-recaptcha-response"].present?
#     uri = URI.parse("https://www.google.com/recaptcha/api/siteverify")
#     response = Net::HTTP.post_form(uri,
#       secret: ENV["RECAPTCHA_SECRET_KEY"],
#       response: params["g-recaptcha-response"]
#     )
#     JSON.parse(response.body)["success"]
#   end

#   def deliver_partner_confirmation(partner)
#     mailer = Partners::PartnerMailer
#     if Rails.env.development?
#       mailer.confirmation(partner).deliver_now
#     else
#       mailer.confirmation(partner).deliver_later
#     end
#   end
# end
