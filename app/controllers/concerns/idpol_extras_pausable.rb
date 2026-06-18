# frozen_string_literal: true

# Pauses the IDPol / law-enforcement "Tier 3" extras for the v1 launch:
# officer analytics, border entries, tickets, officer complaints, and the
# law-enforcement partner-portal search + critical-alert toggle.
#
# The code, routes, and models all remain in place — these entry points just
# redirect away unless the feature is explicitly enabled. v1 keeps the core
# (identity verification, incident reports, officer management).
#
# Re-enable with:  IDPOL_EXTRAS_ENABLED=true
module IdpolExtrasPausable
  extend ActiveSupport::Concern

  # Single source of truth (also used by the view helper to hide nav links).
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("IDPOL_EXTRAS_ENABLED", false))
  end

  class_methods do
    def pause_unless_idpol_extras(**options)
      before_action :ensure_idpol_extras_enabled!, **options
    end
  end

  private

  def ensure_idpol_extras_enabled!
    return if IdpolExtrasPausable.enabled?

    redirect_back fallback_location: root_path,
                  alert: "This feature isn't available yet."
  end
end
