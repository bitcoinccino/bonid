# app/jobs/oauth_event_replay_job.rb
class OauthEventReplayJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = OauthEvent.find(event_id)
    partner = event.oauth_application.partner

    # Example: resend event payload to the partner
    begin
      OauthNotifier.send_event(partner, event)
      event.update!(status: "replayed")
      Rails.logger.info("[OAuthEventReplayJob] Event ##{event.id} replayed successfully")
    rescue => e
      event.update!(status: "replay_failed", last_error: e.message)
      Rails.logger.error("[OAuthEventReplayJob] Failed to replay event ##{event.id}: #{e.message}")
    end
  end
end
