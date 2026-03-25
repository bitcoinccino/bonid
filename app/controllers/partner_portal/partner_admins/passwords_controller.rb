# frozen_string_literal: true

module PartnerPortal
  module PartnerAdmins
    class PasswordsController < Devise::PasswordsController
      layout "partner_portal/partner_admins_auth"
      respond_to :html, :turbo_stream

      # 🔥 CRITICAL: Force Devise mapping BEFORE ANYTHING runs
      before_action :set_devise_mapping
      prepend_before_action :require_no_authentication, only: [ :create, :update ]

      # ==========================================================================
      # FORCE THIS CONTROLLER TO ALWAYS USE partner_admin SCOPE
      # ==========================================================================
      def resource_name
        :partner_admin
      end

      def resource_class
        User
      end

      def devise_mapping
        Devise.mappings[:partner_admin]
      end

      # ==========================================================================
      # CORE FIX — THIS LINE ENDS THE scoped_path ERROR FOREVER
      # ==========================================================================
      def set_devise_mapping
        request.env["devise.mapping"] = Devise.mappings[:partner_admin]
      end

      # ---------------------------------------------------------------------
      # POST /partner_admins/password
      # ---------------------------------------------------------------------
      def create
        self.resource = resource_class.find_by(email: resource_params[:email])

        if resource.nil?
          flash[:alert] = "No account found with that email."
          redirect_to new_partner_admin_session_path and return
        end

        unless resource.has_role?(:partner_admin)
          flash[:alert] = "Only Partner Admin accounts can reset here."
          redirect_to new_partner_admin_session_path and return
        end

        # 🔥 NOW SAFE: Devise knows the mapping, no scoped_path error
        super
      end

      # ---------------------------------------------------------------------
      # PUT /partner_admins/password
      # ---------------------------------------------------------------------
      def update
        self.resource = resource_class.reset_password_by_token(resource_params)

        if resource.blank? || resource.id.blank?
          flash[:alert] = "Invalid or expired reset token. Please request a new one."
          redirect_to new_partner_admin_password_path and return
        end

        fresh_user = User.find_by(id: resource.id)
        unless fresh_user&.has_role?(:partner_admin)
          flash[:alert] = "Invalid account type for this portal."
          redirect_to new_partner_admin_session_path and return
        end

        if resource.errors.empty?
          resource.unlock_access! if unlockable?(resource)

          respond_to do |format|
            format.html do
              flash[:notice] = "Password updated successfully. Please log in."
              redirect_to new_partner_admin_session_path
            end

            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                "flash",
                partial: "shared/flash",
                locals: { notice: "Password updated successfully. Please log in." }
              )
            end
          end

        else
          respond_to do |format|
            format.html { render :edit, status: :unprocessable_entity }
            format.turbo_stream { render :edit, status: :unprocessable_entity }
          end
        end
      end

      # ---------------------------------------------------------------------
      # FIX: FORCE REDIRECT + FLASH WHEN SENDING RESET EMAIL
      # ---------------------------------------------------------------------
      def respond_with(resource, _opts = {})
        if request.format.turbo_stream?
          flash[:notice] = "A reset link has been sent to your email."
          redirect_to new_partner_admin_session_path(format: :html)
        else
          super
        end
      end

      protected

      def after_resetting_password_path_for(_resource)
        new_partner_admin_session_path
      end

      def after_sending_reset_password_instructions_path_for(_scope)
        new_partner_admin_session_path
      end
    end
  end
end
