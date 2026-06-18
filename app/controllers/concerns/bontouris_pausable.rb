# frozen_string_literal: true

# Pauses the BonTouris (visitor / tourist ID) feature for the v1 launch.
#
# The feature's code, routes, and models all remain in place — this guard
# simply intercepts the BonTouris entry points and bounces the request away
# unless the feature is explicitly enabled.
#
# Usage:
#   include BontourisPausable
#   pause_bontouris_unless_enabled                         # gate the whole controller
#   pause_bontouris_unless_enabled only: :some_action      # gate specific actions
#
# To re-enable BonTouris, set the env var:  BONTOURIS_ENABLED=true
# (or remove the calls above).
module BontourisPausable
  extend ActiveSupport::Concern

  # Single source of truth for the flag — also used by the view helper
  # (ApplicationHelper#bontouris_enabled?) to hide nav links while paused.
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("BONTOURIS_ENABLED", false))
  end

  class_methods do
    def pause_bontouris_unless_enabled(**options)
      before_action :ensure_bontouris_enabled!, **options
    end
  end

  private

  def bontouris_enabled?
    BontourisPausable.enabled?
  end

  def ensure_bontouris_enabled!
    return if bontouris_enabled?

    redirect_back fallback_location: root_path,
                  alert: t("main.navbar.coming_badge"),
                  status: :see_other
  end
end
