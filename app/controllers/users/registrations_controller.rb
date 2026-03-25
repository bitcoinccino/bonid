# app/controllers/users/registrations_controller.rb
class Users::RegistrationsController < Devise::RegistrationsController
  before_action :authenticate_user!, only: [ :edit, :update ]

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

    # ✅ Always enforce citizen role as default
    resource.add_role(:citizen)

    if resource.save
      yield resource if block_given?

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
      # Handle email already taken but unconfirmed
      if resource.errors.details[:email].any? { |e| e[:error] == :taken } && !User.find_by(email: resource.email)&.confirmed?
        flash[:alert] = "Email already taken but not confirmed. Please confirm your email or resend confirmation instructions."
        redirect_to new_user_confirmation_path(email: resource.email) and return
      end

      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  private

  def sign_up_params
    params.require(:user).permit(:email, :password, :password_confirmation, :terms)
  end

  def allow_public_signup?
    Rails.application.config.allow_public_signup == true
  end

  def valid_verified_partner?(partner_id)
    partner_id.present? && Partner.exists?(id: partner_id, verified_at: ..Time.current)
  end
end
