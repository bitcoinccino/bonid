# app/controllers/citizens/passwords_controller.rb
module Citizens
  class PasswordsController < Devise::PasswordsController
    layout "citizen_auth"

    # GET /citizens/password/new
    def new
      redirect_to login_path,
                  notice: t("citizen_portal.auth.flash.no_passwords")
    end

    # POST /citizens/password
    def create
      redirect_to login_path,
                  notice: t("citizen_portal.auth.flash.no_passwords")
    end

    # GET /citizens/password/edit?reset_password_token=...
    def edit
      redirect_to login_path,
                  notice: t("citizen_portal.auth.flash.no_passwords")
    end

    # PUT /citizens/password
    def update
      redirect_to login_path,
                  notice: t("citizen_portal.auth.flash.no_passwords")
    end
  end
end
