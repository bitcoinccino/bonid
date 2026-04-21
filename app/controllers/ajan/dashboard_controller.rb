# frozen_string_literal: true

# Agent Portal dashboard. Landing page after sign-in (/ajan/tablo).
# The view dispatches its body partial by current_sector so each
# partner sector (CEP, ONACA, banking, etc.) gets its own widgets.
module Ajan
  class DashboardController < Ajan::ApplicationController
    def show
      # Per-sector data prep. Start with CEP only; other sectors fall
      # through to the generic "welcome" panel.
      case current_sector
      when "cep"
        # Ajan-to-BED/BEK binding isn't modeled yet — invite-time selection
        # exists in the UI (team/confirm.html.erb) but the FK has no
        # column on User. Dashboard shows partner-wide today's count until
        # that binding lands.
        @today_enrollments_count = VoterEligibilityRecord
          .where(registered_by_partner_id: current_partner.id)
          .where("registered_at >= ?", Time.current.beginning_of_day)
          .count
      end
    end
  end
end
