# frozen_string_literal: true

class BroadcastNewVoteJob < ApplicationJob
  queue_as :default

  def perform(election_id)
    stats = ElectionBallot.stats(election_id)
    ElectionTallyChannel.broadcast_vote(election_id, stats)
  rescue => e
    Rails.logger.warn("[BroadcastNewVoteJob] Failed for election #{election_id}: #{e.message}")
  end
end
