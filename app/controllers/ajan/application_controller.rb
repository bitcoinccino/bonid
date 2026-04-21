# frozen_string_literal: true

# Ajan::ApplicationController
# ============================
# Base controller for the Agent Portal ("Pòtay Ajan").
#
# Serves any partner sector that has an agent-tier role — CEP Ajan Enskripsyon,
# ONACA Apantè/Notè, bank agents/tellers, etc. Sidebar + dashboard dispatch by
# sector (@current_partner.department_sector || .sector), same pattern as
# partner_portal/default.html.erb.
#
# Gates (in order):
#   1. authenticate_user!   — Devise; any User session works
#   2. ensure_agent_role    — must hold a partner_agent* / bank_agent / bank_teller rolify role
#   3. ensure_partner       — must be bound to a partner (set at invite time)
#   4. ensure_bonid_verified — field work requires a verified identity
module Ajan
  class ApplicationController < ApplicationController
    layout "ajan"

    before_action :require_ajan_user!
    before_action :ensure_agent_role
    before_action :ensure_partner
    before_action :ensure_bonid_verified
    before_action :ensure_oath_accepted!

    # `current_agent` resolves from session[:ajan_user_id] (set at OTP verify).
    # Warden's :agent scope is also populated via sign_in(:agent, user), but
    # its per-scope session key has proven flaky across redirects on tunnelled
    # domains — the plain session key is the authoritative source here.
    helper_method :current_agent, :current_partner, :current_sector, :current_agent_role_key

    def current_agent
      @current_agent ||= resolve_current_agent
    end

    private

    def resolve_current_agent
      id = session[:ajan_user_id]
      return nil unless id.is_a?(Integer)

      User.find_by(id: id)
    end

    def require_ajan_user!
      return if current_agent

      redirect_to ajan_otp_sign_in_path,
                  alert: "Tanpri konekte pou w antre nan Pòtay Ajan."
    end

    def ensure_agent_role
      return if current_agent_role_key.present?

      sign_out(:agent) if agent_signed_in?
      session.delete(:ajan_user_id)
      redirect_to ajan_otp_sign_in_path,
                  alert: "Ou pa gen aksè nan Pòtay Ajan. Kontakte administratè ekip ou."
    end

    def ensure_partner
      return if current_agent&.partner_id.present?

      sign_out(:agent) if agent_signed_in?
      session.delete(:ajan_user_id)
      redirect_to ajan_otp_sign_in_path,
                  alert: "Ou poko afekte nan yon ekip. Mande administratè ou yon envitasyon."
    end

    def ensure_bonid_verified
      return if current_agent&.bonid_verified?

      redirect_to ajan_otp_sign_in_path,
                  alert: "BonID ou dwe verifye anvan ou ka itilize Pòtay Ajan."
    end

    # Gate every authenticated agent surface behind Ajan::OathController.
    # OathController skips this before_action to break the redirect loop.
    #
    # Acceptance is tracked in the SESSION (not on the User), so every fresh
    # login forces the agent to re-read and re-sign the oath — this is
    # intentional: field agents handle citizen identity in person and the
    # daily re-affirmation is part of the integrity posture. Bumping
    # Ajan::OathController::CURRENT_VERSION also invalidates stale sessions.
    # The User columns (ajan_oath_accepted_at/_version) remain as an audit
    # trail of the most recent acceptance.
    def ensure_oath_accepted!
      return unless current_agent
      return if session[:ajan_oath_accepted_version] == Ajan::OathController::CURRENT_VERSION

      redirect_to ajan_oath_path
    end

    def current_partner
      @current_partner ||= current_agent&.partner
    end

    # Sector drives sidebar partial selection + dashboard widgets.
    # Falls back to "default" when a partner has no sector set.
    def current_sector
      @current_sector ||= (current_partner&.department_sector || current_partner&.sector).to_s.downcase.presence || "default"
    end

    # The specific agent-tier role this user holds on this partner.
    # Returns the first match — users are expected to hold one agent role
    # per partner (enforced at invite time).
    def current_agent_role_key
      return nil unless current_agent

      @current_agent_role_key ||=
        (current_agent.roles.pluck(:name) & GovernmentRoleConstants.agent_role_keys).first
    end
  end
end
