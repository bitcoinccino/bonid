class PartnerPortal::ApplicationController < ApplicationController
  # FIXED: Include Devise helpers for authenticate_user! and current_user
  include Devise::Controllers::Helpers

  # Auth before_actions
  before_action :authenticate_user!  # Require login
  before_action :require_partner_admin!  # Role check
  before_action :set_partner  # @partner convenience

  layout "partner_portal"  # Custom layout if exists

  private

  def require_partner_admin!
    unless current_user.partner_admin?
      flash[:alert] = "Access denied. Partner admins only."
      redirect_to root_path
    end
  end

  def set_partner
    @partner = current_user.partner
  end
end
