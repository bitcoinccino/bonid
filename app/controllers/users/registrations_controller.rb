# app/controllers/users/registrations_controller.rb
class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_permitted_parameters, if: :devise_controller?

  # GET /users/sign_up
  def new
    partner_id = session[:bonid_partner_id]

    unless allow_public_signup? || valid_verified_partner?(partner_id)
      redirect_to partners_path, alert: "🚫 Please start from a verified partner page to get BonID." and return
    end

    super
  end

  # POST /users
  def create
    build_resource(sign_up_params)
    resource.role_int ||= :user

    resource.save
    yield resource if block_given?

    if resource.persisted?
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:role_int])
  end

  private

  def allow_public_signup?
    Rails.application.config.allow_public_signup == true
  end

  def valid_verified_partner?(partner_id)
    partner_id.present? && Partner.exists?(id: partner_id, verified_at: ..Time.current)
  end
end
