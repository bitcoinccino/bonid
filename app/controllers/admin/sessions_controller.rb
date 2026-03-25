# app/controllers/admin/sessions_controller.rb
module Admin
  class SessionsController < Devise::SessionsController
    layout "admin_auth"

    def new
      sign_out_all_scopes

      # ✅ Safely initialize Devise resource
      self.resource = resource_class.new
      clean_up_passwords(resource)

      # ✅ Always render the HTML login page explicitly
      respond_to do |format|
        format.html { render :new, status: :ok }
      end
    end

    def create
      self.resource = warden.authenticate!(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(:admin_user, resource)
      redirect_to after_sign_in_path_for(resource)
    rescue => e
      Rails.logger.error("❌ Admin sign-in failed: #{e.message}")
      redirect_to new_admin_user_session_path, alert: "Invalid credentials."
    end

    def destroy
      sign_out(:admin_user)
      redirect_to after_sign_out_path_for(:admin_user), notice: "Signed out successfully."
    end

    protected

    def after_sign_in_path_for(resource)
      admin_root_path
    end

    def after_sign_out_path_for(_resource)
      new_admin_user_session_path
    end
  end
end
