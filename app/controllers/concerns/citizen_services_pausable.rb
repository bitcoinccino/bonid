# frozen_string_literal: true

# NOTE (v1 launch, 2026-11-10): citizen "Sèvis" (partner service directory)
# and "Aplikasyon Mwen" (my service applications) are PAUSED.
#
# Why: v1 is identity verification + partner API/consents. These pages only
# become useful once partners build and publish application forms (partner
# schemas) in the partner portal. At launch there are none, so citizens would
# land on a directory with no working "Apply" and an always-empty list.
#
# What stays: all code, routes, models and data. Partners can still build
# forms in the partner portal (Services) so they're ready at turn-on.
#
# To turn it back on: set CITIZEN_SERVICES_ENABLED=true. That restores the
# nav links (sidebar + topbar) and these controllers in one switch.
module CitizenServicesPausable
  extend ActiveSupport::Concern

  # Single source of truth — also used by ApplicationHelper#citizen_services_enabled?
  # to hide the nav links while paused.
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("CITIZEN_SERVICES_ENABLED", false))
  end

  included do
    before_action :ensure_citizen_services_enabled!
  end

  private

  def ensure_citizen_services_enabled!
    return if CitizenServicesPausable.enabled?

    redirect_to citizens_dashboard_path, alert: t("main.navbar.services_paused"), status: :see_other
  end
end
