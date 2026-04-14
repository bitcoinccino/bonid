# frozen_string_literal: true

# Aggregated election tally broadcaster.
#
# Instead of broadcasting on EVERY vote (which creates a broadcast storm
# at 500+ votes/sec), this job runs on a 5-second interval and pushes
# a single aggregated update to all connected CEP admin dashboards.
#
# How it works:
#   1. Each vote increments a Redis counter (O(1), ~0.1ms)
#   2. This job checks the counter every 5 seconds
#   3. If new votes arrived, it queries the DB for fresh stats and broadcasts
#   4. If no new votes, it skips (no wasted DB queries)
#
# Start during voting window:
#   BroadcastElectionTallyJob.perform_later(election_id)
#
# It self-re-enqueues every 5 seconds while the election is open.
# Stops automatically when election is closed or certified.
#
class BroadcastElectionTallyJob < ApplicationJob
  queue_as :default

  INTERVAL = 5.seconds

  def perform(election_id)
    # Stop self-scheduling if election is no longer open
    unless ::Election::ElectionCache.open?(election_id)
      Rails.logger.info("[ElectionTally] Election #{election_id} is no longer open. Stopping broadcast loop.")
      # Do one final broadcast with latest stats
      broadcast_stats(election_id)
      return
    end

    # Only broadcast if new votes have arrived since last check
    current_count = ::Election::ElectionCache.vote_count(election_id)
    last_count = Rails.cache.read("election:last_broadcast_count:#{election_id}").to_i

    if current_count > last_count
      broadcast_stats(election_id)
      Rails.cache.write("election:last_broadcast_count:#{election_id}", current_count, expires_in: 1.hour)
    end

    # Re-enqueue self after interval
    self.class.set(wait: INTERVAL).perform_later(election_id)
  rescue => e
    Rails.logger.error("[ElectionTally] Error broadcasting for #{election_id}: #{e.message}")
    # Still re-enqueue on error so we don't lose the loop
    self.class.set(wait: INTERVAL).perform_later(election_id)
  end

  private

  def broadcast_stats(election_id)
    stats = ElectionBallot.stats(election_id)

    # Attach velocity snapshot (no extra DB query — Redis only)
    stats[:velocity] = ::Election::VelocityMonitorService.snapshot(election_id)

    # Attach nullifier collision stats (Redis only)
    stats[:nullifier_collisions] = ::Election::NullifierCollisionTracker.stats(election_id)

    # Attach ceremony progress (1 lightweight DB query)
    stats[:ceremony] = ::Election::CeremonyTracker.broadcast_payload(election_id)

    ElectionTallyChannel.broadcast_vote(election_id, stats)

    # Check for velocity spikes (fires alert if threshold exceeded)
    ::Election::VelocityMonitorService.check_and_alert!(election_id)
  end
end
