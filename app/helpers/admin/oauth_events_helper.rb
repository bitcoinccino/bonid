module Admin::OauthEventsHelper
  def human_event_type(event)
    type = event&.event_type.to_s
    {
      "consent_granted" => "Granted",
      "consent_revoked" => "Revoked",
      "token_issued"    => "Token Issued",
      "token_refreshed" => "Token Refreshed",
      "token_revoked"   => "Token Revoked"
    }[type] || type.titleize.presence || "Unknown"
  end

  def human_event_status(event)
    status = event&.status.to_s
    {
      "replayed"       => "Replay Successful",
      "replay_failed"  => "Failed Replay",
      "success"        => "Success",
      "failed"         => "Failed",
      "pending"        => "Pending"
    }[status] || status.titleize.presence || "Unknown"
  end
end
