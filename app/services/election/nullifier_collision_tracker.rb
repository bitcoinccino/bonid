# frozen_string_literal: true

# Nullifier Collision Tracker — silent alarm for double-vote attempts.
#
# When a voter tries to cast a ballot with a nullifier that already
# exists in the ledger, the vote is silently rejected (idempotent).
# But the ATTEMPT itself is a security signal:
#
#   - 1 attempt: Normal (user refreshed the page, network retry)
#   - 3+ attempts: Suspicious (someone may be trying to forge votes)
#   - 10+ from same IP: Critical (coordinated attack vector)
#
# This tracker records every collision event in Redis and broadcasts
# alerts to the CEP command center without blocking the voter.
#
# Usage:
#   NullifierCollisionTracker.record!(election_id, nullifier:, ip:, channel:)
#   NullifierCollisionTracker.stats(election_id)
#   NullifierCollisionTracker.alerts(election_id)
#
module Election
  class NullifierCollisionTracker
    # Alert thresholds
    SUSPICIOUS_THRESHOLD = 3   # Same nullifier attempted 3+ times
    CRITICAL_THRESHOLD   = 10  # Same IP triggers 10+ collisions

    # Redis key prefixes
    COLLISION_COUNT   = "election:nullifier_collision:count:"
    COLLISION_BY_IP   = "election:nullifier_collision:ip:"
    COLLISION_LOG     = "election:nullifier_collision:log:"
    COLLISION_ALERTS  = "election:nullifier_collision:alerts:"

    # ── Record a collision event ─────────────────────────────────

    def self.record!(election_id, nullifier:, ip_address: nil, channel: "remote", department_code: nil)
      timestamp = Time.current

      # 1. Increment collision count for this specific nullifier
      nullifier_key = "#{COLLISION_COUNT}#{election_id}:#{nullifier}"
      collision_count = $redis.incr(nullifier_key)
      $redis.expire(nullifier_key, 24.hours.to_i)

      # 2. Track collisions per IP address
      ip_collision_count = 0
      if ip_address.present?
        ip_key = "#{COLLISION_BY_IP}#{election_id}:#{ip_address}"
        ip_collision_count = $redis.incr(ip_key)
        $redis.expire(ip_key, 24.hours.to_i)
      end

      # 3. Log the event (capped at 500 events)
      event = {
        nullifier_prefix: nullifier[0..7], # Only first 8 chars for privacy
        collision_number: collision_count,
        ip_hash: ip_address.present? ? OpenSSL::Digest::SHA256.hexdigest(ip_address)[0..11] : nil,
        ip_total_collisions: ip_collision_count,
        channel: channel,
        department_code: department_code,
        timestamp: timestamp.iso8601
      }

      $redis.multi do |r|
        r.lpush("#{COLLISION_LOG}#{election_id}", event.to_json)
        r.ltrim("#{COLLISION_LOG}#{election_id}", 0, 499)
        r.expire("#{COLLISION_LOG}#{election_id}", 24.hours.to_i)
      end

      # 4. Check alert thresholds
      check_and_alert!(election_id, event, collision_count, ip_collision_count)

      event
    end

    # ── Collision statistics ──────────────────────────────────────

    def self.stats(election_id)
      log = raw_log(election_id)

      unique_nullifiers = log.map { |e| e[:nullifier_prefix] }.uniq.size
      unique_ips = log.map { |e| e[:ip_hash] }.compact.uniq.size
      by_channel = log.group_by { |e| e[:channel] }.transform_values(&:size)

      {
        total_collisions: log.size,
        unique_nullifiers_involved: unique_nullifiers,
        unique_ips_involved: unique_ips,
        by_channel: by_channel,
        suspicious_count: log.count { |e| e[:collision_number].to_i >= SUSPICIOUS_THRESHOLD },
        critical_count: log.count { |e| e[:ip_total_collisions].to_i >= CRITICAL_THRESHOLD },
        last_collision_at: log.first&.dig(:timestamp)
      }
    end

    # ── Active alerts ────────────────────────────────────────────

    def self.alerts(election_id)
      raw = $redis.lrange("#{COLLISION_ALERTS}#{election_id}", 0, 49)
      raw.map { |a| JSON.parse(a, symbolize_names: true) }
    rescue
      []
    end

    # ── Recent collision log (for CEP review) ────────────────────

    def self.recent_log(election_id, limit: 20)
      raw_log(election_id).first(limit)
    end

    # ── Reset (for testing) ──────────────────────────────────────

    def self.reset!(election_id)
      keys = $redis.keys("election:nullifier_collision:*#{election_id}*")
      $redis.del(*keys) if keys.any?
    end

    private

    def self.raw_log(election_id)
      raw = $redis.lrange("#{COLLISION_LOG}#{election_id}", 0, 499)
      raw.map { |e| JSON.parse(e, symbolize_names: true) }
    rescue
      []
    end

    def self.check_and_alert!(election_id, event, collision_count, ip_collision_count)
      alert = nil

      if ip_collision_count >= CRITICAL_THRESHOLD && ip_collision_count == CRITICAL_THRESHOLD
        # Critical: same IP generating many collisions (coordinated attack)
        alert = {
          severity: "critical",
          type: "ip_collision_flood",
          message: "IP #{event[:ip_hash]} has #{ip_collision_count} nullifier collisions — possible coordinated attack",
          ip_hash: event[:ip_hash],
          collision_count: ip_collision_count,
          detected_at: Time.current.iso8601
        }
      elsif collision_count >= SUSPICIOUS_THRESHOLD && collision_count == SUSPICIOUS_THRESHOLD
        # Suspicious: same nullifier attempted multiple times
        alert = {
          severity: "warning",
          type: "nullifier_replay",
          message: "Nullifier #{event[:nullifier_prefix]}... attempted #{collision_count} times — possible vote forgery",
          nullifier_prefix: event[:nullifier_prefix],
          collision_count: collision_count,
          channel: event[:channel],
          detected_at: Time.current.iso8601
        }
      end

      return unless alert

      # Persist alert
      $redis.multi do |r|
        r.lpush("#{COLLISION_ALERTS}#{election_id}", alert.to_json)
        r.ltrim("#{COLLISION_ALERTS}#{election_id}", 0, 49)
        r.expire("#{COLLISION_ALERTS}#{election_id}", 24.hours.to_i)
      end

      # Broadcast to CEP dashboard
      ActionCable.server.broadcast(
        "election_tally_#{election_id}",
        { type: "nullifier_collision_alert", alert: alert }
      )

      Rails.logger.warn(
        "[NullifierCollision] #{alert[:severity].upcase}: #{alert[:message]} " \
        "(election #{election_id})"
      )

      alert
    end
  end
end
