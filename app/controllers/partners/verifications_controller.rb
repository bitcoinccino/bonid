# frozen_string_literal: true

module Partners
  class VerificationsController < ApplicationController
    layout "public"

    # -----------------------------------------------------
    # GET /partners/verify?token=XYZ
    # -----------------------------------------------------
    def verify
      token = params[:token].to_s.strip

      if token.blank?
        return render :error, status: :unprocessable_entity
      end

      @partner = Partner.find_by(email_verification_token: token)

      unless @partner
        return render :error, status: :unprocessable_entity
      end

      # Mark email as verified (do NOT clear token yet)
      @partner.update!(verified_at: Time.current)

      PartnerAuditLog.create!(
        partner: @partner,
        event: "email_verified",
        details: {
          ip: request.remote_ip,
          user_agent: request.user_agent
        }
      )

      @redirect_path = next_portal_path(@partner)

      render :success

      # Clear token after rendering to avoid expired-page redirect
      @partner.update_column(:email_verification_token, nil)
    end

    private

    # -----------------------------------------------------
    # Determine which portal to send partner to after verify
    # -----------------------------------------------------
    def next_portal_path(partner)
      case partner.sector
      when "banking"
        partner_portal_banking_dashboard_path
      when "hospital"
        partner_portal_hospital_dashboard_path
      when "embassy"
        partner_portal_embassy_dashboard_path
      when "law_enforcement"
        partner_portal_law_enforcement_dashboard_path
      else
        partner_portal_dashboard_path
      end
    end
  end
end
