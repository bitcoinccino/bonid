# app/controllers/officers/passwords_controller.rb
class Officers::PasswordsController < Devise::PasswordsController
  layout "officer_auth"
  # POST /officers/password (send reset instructions)
  def create
    self.resource = resource_class.send_reset_password_instructions(resource_params)

    if successfully_sent?(resource)
      flash[:notice] = I18n.t("devise.passwords.send_instructions")
      respond_with(resource, location: after_sending_reset_password_instructions_path_for(resource_name))
    else
      flash.now[:alert] = I18n.t("devise.passwords.user_not_found")
      render :new, status: :unprocessable_entity
    end
  end

  # PUT /officers/password (reset password)
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)

    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)

      # Optional audit logging
      Rails.logger.info "🔐 Officer #{resource.email} reset their password at #{Time.current}"

      flash[:notice] = I18n.t("devise.passwords.updated")
      sign_in(resource_name, resource)
      respond_with resource, location: after_resetting_password_path_for(resource)
    else
      set_minimum_password_length
      flash.now[:alert] = I18n.t("devise.passwords.update_failed")
      render :edit, status: :unprocessable_entity
    end
  end

  protected

  # Redirect officer to dashboard after resetting password
  def after_resetting_password_path_for(resource)
    officers_dashboard_path
  end

  # Handle fallback for sending instructions
  def after_sending_reset_password_instructions_path_for(resource_name)
    new_session_path(resource_name)
  end

  private

  def resource_params
    params.require(:officer).permit(:email, :reset_password_token, :password, :password_confirmation)
  end
end
