# frozen_string_literal: true

module Citizens
  class ConsentsController < BaseController
    before_action :authenticate_citizen!
    before_action :set_citizen
    before_action :set_consent, only: %i[destroy show]

    # ======================================================
    # 🔍 Index
    # ======================================================
    def index
      @consent_grants = @citizen.consent_grants
                                .includes(partner: { logo_attachment: :blob })
                                .order(created_at: :desc)
                                .page(params[:page]).per(20)

      respond_to do |format|
        format.html
        format.json { render json: @consent_grants.as_json(include: { partner: { only: %i[id name sector slug] } }) }
      end
    end

    # ======================================================
    # 🟢 Create or approve consent manually from dashboard
    # ======================================================
    def create
      consent = @citizen.consent_grants.find_or_initialize_by(partner_id: consent_params[:partner_id])
      scopes = Array(consent_params[:requested_scopes])
      consent.requested_scopes = scopes
      consent.granted_scopes   = scopes
      consent.status = :approved
      consent.granted_at = Time.current
      consent.expires_at ||= 90.days.from_now
      consent.generate_grant_token if consent.grant_token.blank?

      if consent.save(context: :dashboard)
        System::OauthNotifier.consent_approved(consent).deliver_later rescue nil
        ConsentWebhookJob.perform_later(consent.id, "consent.restored") rescue nil

        redirect_to citizens_consents_path,
                    notice: "✅ Access granted to #{consent.partner&.name || 'Partner'}."
      else
        redirect_to citizens_consents_path,
                    alert: "⚠️ Could not grant access. Please try again."
      end
    end

# ======================================================
# ❌ Revoke access
# ======================================================
    def destroy
      @consent = @citizen.consent_grants.find(params[:id])

      ActiveRecord::Base.transaction do
        @consent.revoke!(reason: "Citizen revoked from dashboard")

        # Revoke all active access tokens for this partner
        OauthAccessToken.where(citizen: @citizen, partner: @consent.partner)
                        .update_all(revoked_at: Time.current)
      end

      # Notify partner (outside transaction — non-critical)
      System::OauthNotifier.consent_revoked(@consent).deliver_later rescue nil

      # Webhook notification (async)
      ConsentWebhookJob.perform_later(@consent.id, "consent.revoked") rescue nil

      @consent_grants = @citizen.consent_grants.includes(partner: { logo_attachment: :blob }).order(created_at: :desc)
      flash.now[:notice] = "Access successfully revoked for #{@consent.partner.name}."

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to citizens_consents_path, notice: "Access revoked." }
      end
    rescue => e
      Rails.logger.error("Consent revocation failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash.now[:alert] = "Could not revoke access. Please try again."
      @consent_grants = @citizen.consent_grants.includes(partner: { logo_attachment: :blob }).order(created_at: :desc)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to citizens_consents_path, alert: "Could not revoke access." }
      end
    end

    # ======================================================
    # 🧾 Detailed view of a single consent
    # ======================================================
    def show; end

    private

    # ------------------------------------------------------
    # Helpers
    # ------------------------------------------------------
    def set_citizen
      @citizen = current_citizen
    end

    def set_consent
      @consent = @citizen.consent_grants.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to citizens_consents_path, alert: "Consent record not found."
    end

    def consent_params
      params.require(:consent_grant).permit(:partner_id, requested_scopes: [])
    end
  end
end
