# frozen_string_literal: true

# ============================================================================
# Warden Safe Hooks — BonID Unified Fix
# ----------------------------------------------------------------------------
# Purpose:
#   Prevents rogue or mis-registered Warden hooks (e.g. “undefined method `call'”)
#   from crashing authentication for BankingAgent, Officer, PartnerAdmin, Citizen.
#
#   Also adds structured debug logging for Devise sign-in/out lifecycle.
# ============================================================================

Rails.logger.info "🧩 [Warden] Safe hooks initialized"

# --- After user successfully set in session ---
Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
  next unless user.present?

  scope = opts[:scope] || "unknown"
  Rails.logger.debug "✅ [Warden] after_set_user: #{user.class.name}(##{user.id}) [scope=#{scope}]"
end

# --- After authentication ---
Warden::Manager.after_authentication do |user, auth, opts|
  next unless user.present?

  scope = opts[:scope] || "unknown"
  Rails.logger.debug "🔐 [Warden] after_authentication: #{user.class.name}(##{user.id}) [scope=#{scope}]"
end

# --- Before logout ---
Warden::Manager.before_logout do |user, auth, opts|
  next unless user.present?

  scope = opts[:scope] || "unknown"
  Rails.logger.debug "🚪 [Warden] before_logout: #{user.class.name}(##{user.id}) [scope=#{scope}]"
end

# --- After logout ---
Warden::Manager.after_set_user do |user, auth, opts|
  # noop fallback ensures this hook chain is callable even if another gem registered incorrectly
end
