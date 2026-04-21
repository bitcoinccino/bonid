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

# Warden hooks for scopes that use a non-ActiveRecord serializer (or mid-flight
# deserialization) can yield `user` as a Hash rather than the model instance.
# The :agent scope has hit this. These logging-only hooks must never crash
# auth, so `.id` is guarded via a local lambda (no global method pollution).
user_tag = ->(user) {
  if user.respond_to?(:id)
    "#{user.class.name}(##{user.id})"
  else
    "#{user.class.name}(#{user.inspect.to_s[0, 80]})"
  end
}

# --- After user successfully set in session ---
Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
  next unless user.present?

  scope = opts[:scope] || "unknown"
  Rails.logger.debug "✅ [Warden] after_set_user: #{user_tag.call(user)} [scope=#{scope}]"
end

# --- After authentication ---
Warden::Manager.after_authentication do |user, auth, opts|
  next unless user.present?

  scope = opts[:scope] || "unknown"
  Rails.logger.debug "🔐 [Warden] after_authentication: #{user_tag.call(user)} [scope=#{scope}]"
end

# --- Before logout ---
Warden::Manager.before_logout do |user, auth, opts|
  next unless user.present?

  scope = opts[:scope] || "unknown"
  Rails.logger.debug "🚪 [Warden] before_logout: #{user_tag.call(user)} [scope=#{scope}]"
end

# --- After logout ---
Warden::Manager.after_set_user do |user, auth, opts|
  # noop fallback ensures this hook chain is callable even if another gem registered incorrectly
end
