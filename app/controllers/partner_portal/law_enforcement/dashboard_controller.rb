module PartnerPortal
  module LawEnforcement
    class DashboardController < PartnerPortal::LawEnforcement::BaseController
      include IdpolExtrasPausable # v1 launch: critical-alert toggle paused unless IDPOL_EXTRAS_ENABLED=true
      pause_unless_idpol_extras only: :toggle_alert

      layout "partner_portal/law_enforcement"

      def index
        @partner = @current_partner

        # Resolve scoped relations — unit-scoped admins only see their unit's data
        scoped_officers  = apply_portal_officer_scope(@partner.officers)
        scoped_incidents = apply_portal_incident_scope(@partner.incident_reports)

        # === Core Stats ===
        @stats = {
          officers:         scoped_officers.count,
          officers_active:  scoped_officers.active.count,
          officers_revoked: scoped_officers.revoked.count,
          incident_reports: scoped_incidents.count,
          qr_scans:         @partner.qr_scans.count,
          qr_scans_today:   @partner.qr_scans.where("created_at >= ?", Time.current.beginning_of_day).count
        }

        # === Incident Report Status Breakdown ===
        @incident_stats = {
          pending_review: scoped_incidents.joins(:incident_reviews)
                            .where(incident_reviews: { decision: :pending }).distinct.count,
          overdue:        scoped_incidents.joins(:incident_reviews)
                            .where(incident_reviews: { decision: :pending })
                            .where("incident_reviews.deadline_at < ?", Time.current).distinct.count,
          approved:       scoped_incidents.where(status: :approved).count,
          submitted:      scoped_incidents.where(status: :submitted).count
        }

        # === Officers (with BonID photo eager loading) ===
        @officers = scoped_officers
                      .includes(user: :identity_submissions)
                      .order(created_at: :desc)
                      .limit(8)

        # === Incident Reports (with officer + BonID photos) ===
        @incident_reports = scoped_incidents
                              .includes(:incident_reviews, officer: { user: :identity_submissions })
                              .order(created_at: :desc)
                              .limit(8)

        # === Border Entries (Tourists) - scoped to the admin's visible officers ===
        officer_ids = scoped_officers.pluck(:id)
        @border_entries = BorderEntry.where(officer_id: officer_ids)
                            .includes(:visitor_submission, :officer)
                            .order(entered_at: :desc)
                            .limit(8)

        @border_stats = {
          total:  BorderEntry.where(officer_id: officer_ids).count,
          today:  BorderEntry.where(officer_id: officer_ids)
                    .where("entered_at >= ?", Time.current.beginning_of_day).count,
          active: BorderEntry.where(officer_id: officer_ids)
                    .where(exited_at: nil)
                    .where("entered_at >= ?", 90.days.ago).count
        }

        # === QR Scans (Citizen verifications — with photos for suspect flagging) ===
        @recent_scans = @partner.qr_scans
                          .includes(identity_submission: { user: :identity_submissions })
                          .order(created_at: :desc)
                          .limit(8)

        # === API / System Health Stats ===
        @api_stats = {
          total: @partner.api_access_logs.count,
          success: @partner.api_access_logs.where(success: true).count,
          failed: @partner.api_access_logs.where(success: false).count,
          today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
        }
      end

      # POST /partner_portal/law_enforcement/dashboard/toggle_alert
      # Toggles Critical Incident mode for the entire portal
      def toggle_alert
        @partner = @current_partner
        was_active = @partner.critical_incident_active?

        if was_active
          @partner.update!(
            critical_incident_active: false,
            critical_incident_message: nil,
            critical_incident_activated_at: nil
          )
        else
          @partner.update!(
            critical_incident_active: true,
            critical_incident_message: params[:message].presence,
            critical_incident_activated_at: Time.current
          )
        end

        # Audit trail
        PartnerAuditLog.log!(
          @partner,
          current_partner_admin,
          was_active ? "critical_incident_deactivated" : "critical_incident_activated",
          { message: params[:message], admin_email: current_partner_admin&.email }
        )

        redirect_to partner_portal_law_enforcement_dashboard_path,
                    notice: was_active ? "Critical incident mode deactivated." : "Critical incident mode activated."
      rescue => e
        redirect_to partner_portal_law_enforcement_dashboard_path,
                    alert: "Failed to toggle alert: #{e.message}"
      end
    end
  end
end
