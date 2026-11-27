# frozen_string_literal: true

module PartnerPortal
  class SettingsController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!

    # GET /partner_portal/settings
    def index
      @partner = @current_partner
    end

    # PATCH /partner_portal/settings/:id
    def update
      @partner = @current_partner

      if @partner.update(settings_params)
        redirect_to partner_portal_settings_path, notice: "Settings updated successfully."
      else
        flash.now[:alert] = "Failed to update settings."
        render :index, status: :unprocessable_entity
      end
    end

    # POST /partner_portal/settings/regenerate_webhook_secret
    # Creates (or rotates) the secret BonID signs webhooks with. Rotating
    # invalidates the old one immediately, so the partner must update their
    # app. Saving triggers delivery of any held webhooks (Partner callback).
    def regenerate_webhook_secret
      partner = @current_partner
      rotated = partner.webhook_secret.present?
      partner.generate_webhook_secret!

      PartnerAuditLog.create!(
        partner:  partner,
        event:    rotated ? "webhook_secret_rotated" : "webhook_secret_created",
        details:  "Webhook signing secret #{rotated ? "rotated" : "created"} from partner settings.",
        metadata: { by_partner_admin_id: current_partner_admin&.id }
      )

      redirect_to partner_portal_settings_path(anchor: "webhook-secret"),
                  notice: rotated ? "New webhook secret created. Update it in your app — the old one no longer works." :
                                    "Webhook secret created. Add it to your app to verify BonID webhooks."
    end

    private

    def settings_params
      params.require(:partner).permit(
        :contact_person, :phone_number, :website, :webhook_url
      )
    end
  end
end
