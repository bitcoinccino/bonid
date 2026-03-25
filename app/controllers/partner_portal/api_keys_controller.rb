# frozen_string_literal: true

module PartnerPortal
  class ApiKeysController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!
    before_action :load_api_stats, only: [:index]
    before_action :load_recent_lookups, only: [:index]
    before_action :load_consent_grants, only: [:index]

    def index
      @partner = @current_partner
      @new_api_key_token = flash[:new_api_key_token]
    end

    # Regenerate the partner's API key
    def create
      new_key = @current_partner.rotate_api_key!
      flash[:new_api_key_token] = new_key
      redirect_to partner_portal_api_keys_path, notice: "API Key regenerated successfully."
    end

    # Generate or refresh a Bearer token for a specific consent grant
    def generate_token
      grant = @current_partner.consent_grants.find(params[:grant_id])

      # Find existing active token for this partner + citizen
      token = OauthAccessToken.where(
        partner: @current_partner,
        citizen_id: grant.citizen_id
      ).active.first

      if token.present?
        # Active token exists — reuse it
        flash[:bearer_token] = token.token
        flash[:bearer_grant_id] = grant.id
      else
        # Create a new token with scopes from the consent grant
        scope_list = Array(grant.granted_scopes.presence || grant.requested_scopes).map(&:to_s)
        token = OauthAccessToken.create!(
          partner: @current_partner,
          citizen_id: grant.citizen_id,
          scopes: scope_list,
          expires_at: 1.hour.from_now
        )
        flash[:bearer_token] = token.token
        flash[:bearer_grant_id] = grant.id
      end

      redirect_to partner_portal_api_keys_path, notice: "Bearer token generated. Copy it — it expires in 1 hour."
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_api_keys_path, alert: "Consent grant not found."
    end

    private

    # Load API usage statistics (single grouped query instead of 3)
    def load_api_stats
      counts = @current_partner.api_access_logs.group(:success).count
      total = counts.values.sum
      success = counts[true].to_i
      avg_latency = @current_partner.api_access_logs
                      .where.not(duration_ms: nil)
                      .average(:duration_ms)&.round(1) || 0

      @api_stats = {
        total: total,
        success: success,
        failed: counts[false].to_i,
        success_rate: total > 0 ? ((success.to_f / total) * 100).round(1) : 0,
        avg_latency: avg_latency
      }
    end

    # Load recent BonID lookups from API access logs
    def load_recent_lookups
      @recent_lookups = @current_partner.api_access_logs
                          .includes(:user)
                          .order(created_at: :desc)
                          .limit(20)
    end

    # Load citizens who have granted consent to this partner
    def load_consent_grants
      @consent_grants = @current_partner.consent_grants
                          .includes(citizen: :identity_submissions)
                          .order(created_at: :desc)
                          .page(params[:page]).per(20)

      consent_counts = @current_partner.consent_grants.group(:status).count
      active_count = @current_partner.consent_grants
                       .where(status: :approved)
                       .where("expires_at > ?", Time.current).count

      @consent_stats = {
        total: consent_counts.values.sum,
        active: active_count,
        pending: consent_counts["pending"].to_i,
        revoked: consent_counts["revoked"].to_i
      }
    end
  end
end
