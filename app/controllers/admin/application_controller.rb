module Admin
  class ApplicationController < ::ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin!
    before_action :ensure_guidelines_confirmed

    private

    def require_admin!
      unless current_user&.admin? || current_user&.reviewer?
        redirect_to root_path, alert: "Access denied."
      end
    end
      

    def ensure_admin!
      redirect_to root_path, alert: "Access denied." unless current_user&.admin?
    end

    def ensure_guidelines_confirmed
      return unless current_user.admin?

      unless session[:admin_guidelines_confirmed]
        redirect_to admin_guidelines_path, alert: "Please confirm the admin guidelines before proceeding."
      end
    end
  end

  def after_sign_in_path_for(resource)
    if resource.admin?
      session[:admin_guidelines_confirmed] ? admin_identity_submissions_path : admin_guidelines_path
    elsif resource.reviewer?
      reviewer_dashboard_path
    elsif profile_complete?(resource)
      user_dashboard_path
    else
      edit_profile_path
    end
  end
  

  def after_sign_out_path_for(_resource_or_scope)
    session.delete(:admin_guidelines_confirmed) # 🔄 Clear confirmation on logout
    root_path
  end
end

