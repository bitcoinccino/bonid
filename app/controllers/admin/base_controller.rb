# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ApplicationController
    layout "admin"

    # 🔒 Only enforce admin authentication
    before_action :authenticate_admin!

    # ⛔ Skip partner/session callbacks that break admin pages
    skip_before_action :store_partner_context
    skip_before_action :set_partner_from_slug
    skip_before_action :enforce_namespace_access
    skip_before_action :ensure_active_account!

    private

    def authenticate_admin!
      unless current_admin_user
        redirect_to root_path, alert: "You are not authorized."
      end
    end
  end
end
