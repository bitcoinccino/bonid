# app/controllers/officers/base_controller.rb
# frozen_string_literal: true

module Officers
  class BaseController < ApplicationController
    # ✅ Rails 8 CSRF safety
    # Prevents ArgumentError if callback isn't defined yet
    # skip_before_action :verify_authenticity_token, raise: false

    before_action :authenticate_officer!
    before_action :ensure_officer_not_revoked!
    before_action :ensure_user_has_bonid, unless: :invitation_or_onboarding_flow?
    before_action :ensure_officer_profile_complete, unless: :invitation_or_onboarding_flow?
    before_action :ensure_guidelines_confirmed, unless: :skip_guidelines_check?
    before_action :block_officer_on_user_routes
    before_action :ensure_parent_partner_active!, if: :officer_has_partner?

    layout "officers"

    private

    # 🚫 Prevent officers from accessing user-facing routes
    def block_officer_on_user_routes
      if request.path.start_with?("/users") && officer_signed_in?
        message = "⚠️ Officers must use the IDPol portal to access their account."
        sign_out current_officer   # resets session; write flash into the NEW session after
        flash[:alert] = message
        redirect_to root_path
      end
    end

    # ✅ Ensure officer has a verified BonID before accessing the dashboard
    def ensure_user_has_bonid
      return redirect_to new_officer_session_path, alert: "Please sign in first." if current_officer.nil?

      return if current_officer.identity_submissions.approved.exists?

      message = "You must verify your BonID first."
      sign_out(current_officer)   # resets session; write flash into the NEW session after
      flash[:alert] = message
      redirect_to new_officer_session_path
    end

    # 🧩 Allow invitation and onboarding flows without enforcement
    def invitation_or_onboarding_flow?
      controller_name.in?(%w[invitations onboarding])
    end

    # ✅ Ensure officer has completed their profile (Officer record exists)
    def ensure_officer_profile_complete
      return if current_officer.nil?

      # If current_officer is a User with officer role but no Officer record
      if current_officer.respond_to?(:officer) && current_officer.officer.blank?
        redirect_to officers_onboarding_path, alert: "Please complete your officer profile first."
      end
    end

    def officer_has_partner?
      current_officer&.partner.present?
    end

    def ensure_officer_not_revoked!
      return unless current_officer&.respond_to?(:revoked?)
      return unless current_officer.revoked?

      # ⚠️  sign_out calls warden.logout which calls reset_session, destroying the
      # entire Rails session (including the flash store). We must:
      #   1. Save the message in a local variable
      #   2. Sign out (session is now reset/new)
      #   3. Write into the NEW session's flash so it survives to the next request
      message = "Votre accès a été révoqué. Veuillez contacter votre administrateur."
      sign_out current_officer
      flash[:error] = message
      redirect_to new_officer_session_path
    end

    def ensure_parent_partner_active!
      if current_officer.partner.deleted? || current_officer.partner.suspended?
        message = "Partner account is suspended."
        sign_out current_officer   # resets session; write flash into the NEW session after
        flash[:alert] = message
        redirect_to officers_root_path
      end
    end

    # ✅ Ensure officer has acknowledged guidelines before accessing dashboard
    # Source of truth: guidelines_confirmed_at on the associated users table.
    # Session is used as a cache to avoid a DB hit on every request.
    def ensure_guidelines_confirmed
      return unless current_officer

      # Fast path — session cache is warm
      return if session[:officer_guidelines_confirmed]

      # DB fallback — session expired but officer confirmed historically
      # guidelines_confirmed_at lives on User, not Officer
      confirmed_at = current_officer.user&.guidelines_confirmed_at
      if confirmed_at.present?
        session[:officer_guidelines_confirmed]    = true
        session[:officer_guidelines_confirmed_at] = confirmed_at.to_s
        return
      end

      # Neither session nor DB — officer has never confirmed; must see the page
      redirect_to officers_guidelines_path,
                  alert: "Veuillez confirmer les directives avant de continuer."
    end

    # 🧩 Skip guidelines check for certain flows
    def skip_guidelines_check?
      invitation_or_onboarding_flow? || controller_name.in?(%w[guidelines])
    end

    # ============================================================
    # UNIT + RANK ACCESS CONTROL HELPERS
    # Delegates to OfficerAccessControl concern on Officer model.
    # ============================================================

    # Returns the current officer's rank group symbol (:field / :supervisor / :strategic).
    # Memoised per request.
    def current_officer_rank_group
      @current_officer_rank_group ||= current_officer.rank_group
    end

    # Returns the analytics scope ceiling for the current officer.
    def current_officer_max_scope
      @current_officer_max_scope ||= current_officer.max_analytics_scope
    end

    # Guard: only supervisor or strategic rank officers may pass.
    # Redirect field-rank officers to their dashboard with a French access error.
    def require_supervisor_or_higher!
      return if current_officer.supervisor_rank? || current_officer.strategic_rank?
      redirect_to officers_dashboard_path,
                  alert: "Accès refusé. Rôle insuffisant pour cette action."
    end

    # Guard: only strategic rank officers may pass.
    def require_strategic_rank!
      return if current_officer.strategic_rank?
      redirect_to officers_dashboard_path,
                  alert: "Accès refusé. Réservé aux officiers de direction."
    end

    # Guard: checks whether the current officer may open a specific incident report.
    # Enforces two special rules beyond the standard visibility scope:
    #   1. Internal Affairs reports (Police Brutality) → Inspector General role only
    #   2. Restricted unit reports (USGPN/USP) → same-unit officers only
    # Strategic-rank officers bypass both checks.
    def require_access_to_report!(report)
      return if current_officer.strategic_rank?

      # Internal Affairs: police brutality reports locked to Inspector General role
      ia_types = OfficerConstants::UNIT_ACCESS_SCOPE[:internal_affairs][:trigger_crime_types]
      if ia_types.include?(report.crime_type.to_s) && !current_officer.inspector_general?
        redirect_to officers_incident_reports_path,
                    alert: "Accès refusé. Ce dossier est soumis au contrôle interne uniquement (IGPNH)."
        return
      end

      # Restricted units: only same-unit officers may view these reports
      reporting_unit = report.officer&.unit_name.to_s
      if OfficerConstants::RESTRICTED_UNITS.include?(reporting_unit)
        unless current_officer.unit_name.to_s == reporting_unit
          redirect_to officers_incident_reports_path,
                      alert: "Accès refusé. Ce dossier appartient à une unité à accès restreint."
        end
      end
    end
  end
end
