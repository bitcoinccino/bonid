# app/controllers/users/passwords_controller.rb
class Users::PasswordsController < Devise::PasswordsController
  def update
    raw_token = resource_params[:reset_password_token]
    hashed_token = Devise.token_generator.digest(User, :reset_password_token, raw_token)
    Rails.logger.debug "Password reset attempt: Raw token: #{raw_token}, Hashed token: #{hashed_token}"

    self.resource = resource_class.find_by(reset_password_token: hashed_token)
    Rails.logger.debug "User lookup: ID: #{resource&.id}, Email: #{resource&.email}, Sent at: #{resource&.reset_password_sent_at}"

    unless resource
      Rails.logger.debug "No user found for token. Rendering form with error."
      self.resource = User.new
      resource.errors.add(:reset_password_token, "is invalid")
      set_minimum_password_length
      return respond_with resource
    end

    self.resource = resource_class.reset_password_by_token(resource_params)
    Rails.logger.debug "Reset result: User ID: #{resource&.id}, Email: #{resource&.email}, Errors: #{resource.errors.full_messages}, Sent at: #{resource&.reset_password_sent_at}"

    yield resource if block_given?

    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)

      if resource.has_role?(:partner_admin)
        sign_in(resource)
        set_flash_message!(:notice, :updated)
        respond_with resource, location: ::UserRedirectService.after_sign_in_path_for(resource)
      else
        set_flash_message!(:notice, :updated_not_logged_in)
        respond_with resource, location: new_session_path(resource_name)
      end
    else
      Rails.logger.debug "Submitted params: #{resource_params.inspect}"
      set_minimum_password_length
      respond_with resource
    end
  end
end
