# app/controllers/users/sessions_controller.rb
module Users
  class SessionsController < Devise::SessionsController
    protected

    def after_sign_in_path_for(resource)
      if resource.admin?
        session[:admin_guidelines_confirmed] ? admin_identity_submissions_path : admin_guidelines_path
      elsif resource.reviewer?
        reviewer_dashboard_path
      elsif resource.partner?
        partners_path
      elsif profile_complete?(resource)
        user_dashboard_path
      else
        edit_profile_path
      end
    end

    def after_sign_out_path_for(_resource_or_scope)
      root_path
    end
  end
end
