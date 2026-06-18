class MainController < ApplicationController
  #
  # Force public layout — prevents partner portal overrides
  #
  layout "application"

  #
  # Prevent logged-in users (officers, partner admins, banking agents, etc.)
  # from seeing public pages like home/pricing/faq.
  #
  before_action :redirect_authenticated_user,
                only: [ :home, :required_documents, :terms, :privacy, :pricing ]

  def home
    @waitlist_signup = WaitlistSignup.new
    @departments = Department.order(:name)
    @total_signups = WaitlistSignup.count
    # Verified partners for the constellation "trusted by" grid.
    # Capped at 8 so the grid fills cleanly (2 rows × 4 cols on lg);
    # /partners is the full directory.
    @verified_partners = Partner.where.not(verified_at: nil).order(:name).limit(8)
    render "landing/index"
  end

  def pricing; end



  def partners
    @partners = Partner.where.not(verified_at: nil).order(:name)
    Rails.logger.info "Verified partners: #{@partners.map { |p| [ p.id, p.name, p.verified_at, p.sector ] }}"

    @partners = @partners.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
    @partners = @partners.where(sector: params[:sector]) if params[:sector].present?
  end

  def required_documents; end
  def terms; end
  def privacy; end

  def start
    partner_slug = params[:partner]

    # No partner selected
    if partner_slug.blank?
      if Rails.application.config.allow_public_signup
        session[:bonid_partner_id] = nil
        redirect_to signup_path, notice: "Starting public BonID registration."
      else
        redirect_to partners_path, alert: "ℹ️ Please choose a verified partner to begin."
      end
      return
    end

    # Find partner
    partner = Partner.find_by(slug: partner_slug)
    unless partner
      redirect_to partners_path, alert: "🚫 Partner not found."
      return
    end

    # Unverified partner
    unless partner.verified_at.present?
      redirect_to partners_path, alert: "🚫 This partner is not yet verified."
      return
    end

    # Success → redirect to citizen signup
    session[:bonid_partner_id] = partner.id
    Rails.logger.info "🔐 Partner session set: #{partner.name} (ID: #{partner.id})"

    redirect_to signup_path(partner: partner.slug)
  end

  private

  #
  # Prevent logged-in users from seeing public pages
  #
  def redirect_authenticated_user
    # Allow OAuth callbacks to land on home — partner redirect_uri may point here.
    # grant_token + status params indicate an OAuth callback; let the page render.
    return if params[:grant_token].present? && params[:status].present?

    resource = nil
    resource ||= current_officer if respond_to?(:current_officer)
    resource ||= current_citizen if respond_to?(:current_citizen) && current_citizen.present?
    resource ||= current_user if respond_to?(:current_user)
    return unless resource

    path = RoleRedirectService.redirect_path_for(resource)
    redirect_to path
  end
end
