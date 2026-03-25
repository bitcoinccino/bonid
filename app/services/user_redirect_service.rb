# app/services/user_redirect_service.rb
class UserRedirectService
  class << self
    def after_sign_in_path_for(user, session)
      case
      when user.admin?
        resolve_admin_path(session)
      when user.partner_admin?
        resolve_partner_admin_path
      when user.reviewer?
        resolve_reviewer_path
      when user.officer?
        resolve_officer_path(user)
      when user.citizen?
        resolve_citizen_path(user)
      when user.banker?
        resolve_banker_path
      when user.embassy?
        resolve_embassy_path
      when user.hospital?
        resolve_hospital_path
      else
        Rails.logger.warn("⚠️ Unknown role for user #{user.id} — redirecting to root")
        default_path
      end
    end

    private

    # --- Officers ---
    def resolve_officer_path(user)
      if user.has_verified_bonid?
        helpers.officers_dashboard_path
      else
        # ⚠️ Set a clear message for unverified officers
        ActionDispatch::Request.new(Rails.application.env_config).flash[:alert] =
          "⚠️ You must verify your BonID before accessing the Officer Portal."
        helpers.new_identity_submission_path
      end
    end

    # --- Citizens ---
    def resolve_citizen_path(user)
      if user.identity_submissions.any?
        helpers.user_dashboard_path
      else
        helpers.new_identity_submission_path
      end
    end

    # other role methods unchanged...
    # resolve_admin_path, resolve_partner_admin_path, etc.

    def default_path
      helpers.root_path
    end

    def helpers
      Rails.application.routes.url_helpers
    end
  end
end
