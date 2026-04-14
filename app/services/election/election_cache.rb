# frozen_string_literal: true

# Redis-backed cache for hot election data.
#
# During voting day, the election status and CEP public key are read
# on EVERY request (eligibility check + cast). Hitting Postgres each
# time wastes ~1–2ms per vote. This cache eliminates those reads.
#
# Cache entries auto-expire after 30 seconds, so status transitions
# (open → closed) propagate within half a minute. For instant
# propagation, call ElectionCache.invalidate!(election_id) when
# CEP changes election status.
#
# Usage:
#   ElectionCache.open?(election_id)       # cached, avoids DB hit
#   ElectionCache.cep_public_key(election_id)
#   ElectionCache.invalidate!(election_id) # call on status change
#
module Election
  class ElectionCache
    CACHE_TTL = 30.seconds
    STATUS_PREFIX = "election:status:"
    KEY_PREFIX    = "election:cep_key:"
    VOTE_COUNTER  = "election:votes:"

    # ── Status Check (replaces BonvoteElection.find_by + .open?) ──

    def self.open?(election_id)
      status(election_id) == "open"
    end

    def self.status(election_id)
      Rails.cache.fetch("#{STATUS_PREFIX}#{election_id}", expires_in: CACHE_TTL) do
        BonvoteElection.find_by(id: election_id)&.status
      end
    end

    # ── CEP Public Key (read once, cached for duration) ──

    def self.cep_public_key(election_id)
      Rails.cache.fetch("#{KEY_PREFIX}#{election_id}", expires_in: 5.minutes) do
        BonvoteElection.find_by(id: election_id)&.cep_public_key ||
          Rails.application.credentials.dig(:election, :cep_public_key) || ""
      end
    end

    # ── Vote Counter (Redis atomic increment, no DB query) ──
    # Used by the aggregated broadcast to know if new votes arrived.

    def self.increment_vote_count!(election_id)
      $redis.incr("#{VOTE_COUNTER}#{election_id}")
    end

    def self.vote_count(election_id)
      $redis.get("#{VOTE_COUNTER}#{election_id}").to_i
    end

    # ── Cache Invalidation ──
    # Call when CEP changes election status (open/close/certify).

    def self.invalidate!(election_id)
      Rails.cache.delete("#{STATUS_PREFIX}#{election_id}")
      Rails.cache.delete("#{KEY_PREFIX}#{election_id}")
      Rails.logger.info("[ElectionCache] Invalidated cache for election #{election_id}")
    end

    # Reset vote counter (call when election opens or for testing).
    def self.reset_vote_counter!(election_id)
      $redis.del("#{VOTE_COUNTER}#{election_id}")
    end
  end
end
