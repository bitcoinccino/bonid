
class Officers::RegistrationsController < Devise::RegistrationsController
  before_action :block_if_user_signed_in
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  # After sign up
  def after_sign_up_path_for(resource)
    flash[:notice] = "Welcome to BonID, Officer. Please complete your profile and begin verifying BonIDs."
    officers_dashboard_path
  end

  # After update (e.g., password change)
  def after_update_path_for(resource)
    flash[:notice] = "Your profile has been updated."
    edit_officers_profile_path
  end

  # 🚫 Block normal users from accessing officer registration
  def block_if_user_signed_in
    if user_signed_in?
      flash[:alert] = "You are not authorized to access the officer portal."
      redirect_to root_path
    end
  end

  # 👮🏻‍♂️ Permit additional officer fields
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :badge_id, :unit_name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :unit_name])
  end
end
 
