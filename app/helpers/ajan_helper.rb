# frozen_string_literal: true

# AjanHelper
# ===========
# View helpers for the Agent Portal, shared across:
#   - authenticated controllers (inherit Ajan::ApplicationController, :user scope)
#   - Devise pages (Ajan::SessionsController / PasswordsController, :agent scope)
#
# The key constraint: Devise auto-generates `current_agent` for the :agent
# scope, so we do NOT redefine it here — instead we expose a neutrally-named
# `ajan_user` that works on every surface, and `current_partner`/`current_sector`
# built on top of it.
#
# On authenticated pages Ajan::ApplicationController ALSO defines helper_method
# :current_agent, :current_partner, :current_sector — those win there.
module AjanHelper
  # Returns the best-available logged-in User across scopes, or nil on the
  # sign-in page where nobody is signed in yet.
  def ajan_user
    return current_user if defined?(current_user) && current_user.is_a?(User)
    # Devise's :agent-scoped helper. Guard .is_a?(User) because warden can
    # return raw session data (Hash/Array) if deserialization misfires.
    if respond_to?(:current_agent)
      candidate = current_agent
      return candidate if candidate.is_a?(User)
    end

    nil
  rescue NameError
    nil
  end

  def current_partner
    ajan_user&.partner
  end

  def current_sector
    sector = (current_partner&.department_sector || current_partner&.sector).to_s.downcase
    sector.presence || "default"
  end

  def current_agent_role_key
    user = ajan_user
    return nil unless user

    (user.roles.pluck(:name) & GovernmentRoleConstants.agent_role_keys).first
  end
end
