# app/controllers/partner_portal/dashboard_controller.rb
module PartnerPortal
  class DashboardController < PartnerPortal::BaseController
    layout "partner_portal/default"

    def index
      unless @current_partner
        redirect_to partner_portal_applications_path, alert: "No partner profile associated." and return
      end

      unless @current_partner.verified_at?
        redirect_to partner_portal_applications_path, alert: "Partner verification required." and return
      end

      # Check if profile needs completion (for PNH minimal signups)
      if profile_incomplete?
        redirect_to partner_portal_profile_completion_path,
                    notice: "Please complete your profile to access your dashboard." and return
      end

      # Check department_sector first (new system), then fallback to sector (legacy)
      partner_sector = @current_partner.department_sector || @current_partner.sector

      case partner_sector&.downcase
      when "pnh", "law_enforcement"
        redirect_to partner_portal_law_enforcement_dashboard_path and return
      end

      # Default dashboard for all other sectors
      load_default_dashboard_data
    end

    private

    def load_default_dashboard_data
      @partner = @current_partner

      # Stats
      @stats = {
        qr_scans: @partner.qr_scans.count,
        qr_scans_today: @partner.qr_scans.where("created_at >= ?", Time.current.beginning_of_day).count,
        verifications: @partner.verification_records.count,
        consent_grants: @partner.consent_grants.count
      }

      # Recent activity
      @recent_scans = @partner.qr_scans
                        .includes(identity_submission: :user)
                        .order(created_at: :desc)
                        .limit(10)

      @recent_verifications = @partner.verification_records
                                .order(created_at: :desc)
                                .limit(10)

      # API stats
      @api_stats = {
        total: @partner.api_access_logs.count,
        success: @partner.api_access_logs.where(success: true).count,
        failed: @partner.api_access_logs.where(success: false).count,
        today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
      }

      # Consent grants (citizens who authorized this partner)
      @consent_grants = @partner.consent_grants
                          .includes(:citizen)
                          .where(status: :approved)
                          .order(created_at: :desc)
                          .limit(10)

      # Transaction consents (ephemeral per-transaction approvals)
      @transaction_consents = @partner.transaction_consents
                                .includes(:citizen)
                                .order(created_at: :desc)
                                .limit(10)
    end

    def profile_incomplete?
      # Required fields for profile completion
      @current_partner.description.blank? ||
        @current_partner.contact_person.blank? ||
        @current_partner.phone_number.blank?
    end
  end
end
