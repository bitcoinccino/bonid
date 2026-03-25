# frozen_string_literal: true

# ActionCable channel for real-time election tally updates.
#
# CEP admins and observers subscribe to this channel to see
# live vote counts without refreshing the page.
#
# Broadcasts on every new ballot:
#   ElectionTallyChannel.broadcast_to(election_id, { total: 1234, remote: 900, consulate: 334 })
#
class ElectionTallyChannel < ApplicationCable::Channel
  def subscribed
    stream_from "election_tally_#{params[:election_id]}"
  end

  def unsubscribed
    # Cleanup
  end

  # Broadcast updated stats to all connected CEP admins
  def self.broadcast_vote(election_id, stats)
    ActionCable.server.broadcast(
      "election_tally_#{election_id}",
      {
        type: "vote_update",
        total_votes: stats[:total_votes],
        remote_votes: stats[:remote_votes],
        consulate_votes: stats[:consulate_votes],
        rejected: stats[:rejected],
        by_country: stats[:by_country],
        timestamp: Time.current.iso8601
      }
    )
  end
end
