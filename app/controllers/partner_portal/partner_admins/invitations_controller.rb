# app/controllers/partner_portal/partner_admin/invitations_controller.rb
module PartnerPortal
  module PartnerAdmins
    class InvitationsController < Devise::InvitationsController
      layout "partner_portal/public"

      protected

      # ------------------------------------------------------------
      # After invite is sent (Partner Admin inviting agents)
      # ------------------------------------------------------------
      def after_invite_path_for(_inviter, _invitee = nil)
        partner_portal_partner_admin_dashboard_path
      end

      # ------------------------------------------------------------
      # After invite is accepted (invited user clicking the link)
      # ------------------------------------------------------------
      def after_accept_path_for(resource)
        # Set success flash message
        flash[:notice] = "✅ Account activated successfully! Please sign in to continue."

        # Redirect to partner admin sign in page
        new_partner_admin_session_path
      end

      private

      # 🧩 Find inviter’s partner based on invitation token
      def inviter_partner_from_token
        token = params[:invitation_token]
        invite = User.find_by_invitation_token(token, true)
        invite&.partner
      rescue => e
        Rails.logger.error("⚠️ inviter_partner_from_token failed: #{e.message}")
        nil
      end
    end
  end
end
