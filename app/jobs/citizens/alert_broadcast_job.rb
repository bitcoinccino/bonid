# frozen_string_literal: true

# Re-renders the citizen's notification bell over Turbo Streams so the
# badge on the topbar refreshes in real time when a new event hits any
# of the sources counted by Citizens::AlertCounter.
module Citizens
  class AlertBroadcastJob < ApplicationJob
    queue_as :default

    def perform(citizen_id)
      citizen = User.find_by(id: citizen_id)
      return unless citizen

      Turbo::StreamsChannel.broadcast_replace_to(
        "citizen_alerts:#{citizen.id}",
        target:  "citizen_alert_bell",
        partial: "citizens/shared/alert_bell",
        locals:  { current_citizen: citizen }
      )
    end
  end
end
