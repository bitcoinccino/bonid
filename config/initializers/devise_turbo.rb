# config/initializers/devise_turbo.rbMake Devise work with Turbo responses
Rails.application.config.to_prepare do
  Devise::SessionsController.respond_to :html, :turbo_stream
  Devise::RegistrationsController.respond_to :html, :turbo_stream
  Devise::PasswordsController.respond_to :html, :turbo_stream
end
