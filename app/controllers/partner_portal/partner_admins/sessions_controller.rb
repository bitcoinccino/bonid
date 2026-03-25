# frozen_string_literal: true

module PartnerPortal
  module PartnerAdmins
    class SessionsController < Devise::SessionsController
      layout "partner_portal/partner_admin_signin"
      respond_to :html

      # === GET /partner_admins/sign_in ===
      def new
        self.resource = resource_class.new
        clean_up_passwords(resource)
        render :new, locals: { resource: resource }
      end

      # === POST /partner_admins/sign_in ===
      def create
        self.resource = warden.authenticate!(auth_options)

        # ✅ Sector + role guard (safe, no assumptions)
        unless partner_admin_account?(resource)
          sign_out(resource) if signed_in?
          return redirect_to new_partner_admin_session_path,
                             alert: "⚠️ This account is not authorized as a Partner Admin."
        end

        set_flash_message!(:notice, :signed_in)
        sign_in(resource_name, resource)
        redirect_to after_sign_in_path_for(resource)

      rescue ::StandardError => e
        Rails.logger.error("❌ PartnerAdmin sign-in failed: #{e.class} - #{e.message}")
        redirect_to new_partner_admin_session_path, alert: "Invalid credentials."
      end

      # === DELETE /partner_admins/sign_out ===
      def destroy
        signed_out = sign_out(resource_name)
        flash[:notice] = "Signed out successfully." if signed_out
        redirect_to after_sign_out_path_for(resource_name)
      end

      protected

      def after_sign_in_path_for(resource)
        params[:return_to].presence || ::PartnerPortalRouter.dashboard_path_for(resource)
      end

      def after_sign_out_path_for(_resource_or_scope)
        new_partner_admin_session_path
      end

      private

      # Handles both patterns:
      # - resource.has_role?(:partner_admin)
      # - resource.partner_admin? (Devise-ish / enum-ish)
      def partner_admin_account?(resource)
        return false unless resource

        if resource.respond_to?(:has_role?)
          resource.has_role?(:partner_admin)
        elsif resource.respond_to?(:partner_admin?)
          resource.partner_admin?
        else
          # If PartnerAdmin is a dedicated model, just being this resource is enough.
          resource.class.name == "PartnerAdmin"
        end
      end
    end
  end
end
