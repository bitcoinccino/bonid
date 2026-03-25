# frozen_string_literal: true

module PartnerApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    # 1️⃣ Always authenticate the API key first
    before_action :authenticate_partner_api_key!

    # 2️⃣ Then enforce partner state
    before_action :ensure_partner_is_active!
    before_action :ensure_partner_not_suspended!
  end

  # ============================================================
  # 1️⃣ API KEY AUTHENTICATION
  # ============================================================
  private

  def authenticate_partner_api_key!
    # Skip auth for consent approval callback
    if request.path.include?("/approve_consent")
      Rails.logger.info "[API AUTH] Skipping partner auth for consent flow."
      return true
    end

    api_key = request.headers["X-Partner-Api-Key"].to_s.strip

    if api_key.blank?
      return render_api_error("Missing API key", :unauthorized)
    end

    @current_partner = Partner.find_by_api_key(api_key)

    unless @current_partner&.active? && @current_partner&.verified?
      return render_api_error("Invalid or inactive API key", :unauthorized)
    end

    Rails.logger.info "[API AUTH] Partner #{@current_partner.slug} authenticated."
  end

  # ============================================================
  # 2️⃣ PARTNER STATE CHECKS
  # ============================================================
  def ensure_partner_is_active!
    return if @current_partner&.active?

    render_api_error("Partner inactive", :forbidden)
  end

  def ensure_partner_not_suspended!
    return unless @current_partner&.suspended?

    render_api_error("Partner suspended", :forbidden)
  end

  # ============================================================
  # 3️⃣ JSON + HTML SAFE RESPONSES
  # ============================================================
  def render_api_error(message, status)
    respond_to do |format|
      format.json  { render json: { error: message }, status: }
      format.html  { redirect_to partner_portal_dashboard_path, alert: message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "flash",
          partial: "shared/flash",
          locals: { alert: message }
        ), status: :unauthorized
      end
    end
  end

  # ============================================================
  # 4️⃣ Expose helper
  # ============================================================
  def current_partner
    @current_partner
  end
end

#
# module PartnerApiAuthenticatable
#   extend ActiveSupport::Concern

#   included do
#     before_action :authenticate_partner_api_key!
#   end

#   private

#   def authenticate_partner_api_key!
#     if request.path.include?("/approve_consent")
#       Rails.logger.info "[API AUTH] Skipping partner auth for consent flow."
#       return true
#     end

#     api_key = request.headers["X-Partner-Api-Key"].to_s.strip
#     if api_key.blank?
#       render json: { error: "Missing API key" }, status: :unauthorized and return
#     end

#     @current_partner = Partner.find_by_api_key(api_key)
#     unless @current_partner&.active? && @current_partner&.verified?
#       render json: { error: "Invalid or inactive API key" }, status: :unauthorized and return
#     end

#     Rails.logger.info "[API AUTH] Partner #{@current_partner.slug} authenticated."
#   end
# end
