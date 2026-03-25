class Admin::ApplicationController < ::ApplicationController
  include Pundit::Authorization
  layout "admin"

  before_action :authenticate_admin_user!
  before_action :ensure_guidelines_confirmed

  private

  def pundit_user
    current_admin_user
  end

  def ensure_guidelines_confirmed
    return unless current_admin_user
    return if session[:admin_guidelines_confirmed]

    if controller_name != "guidelines"
      redirect_to admin_guidelines_path,
                  alert: "Please confirm guidelines before proceeding."
    end
  end
end
