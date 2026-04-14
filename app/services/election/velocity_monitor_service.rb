# frozen_string_literal: true

# Election Velocity Monitor — real-time vote rate anomaly detection.
#
# Tracks votes per 5-second window using Redis sliding counters.
# Detects surges that could indicate:
#   - Bot attacks (coordinated automated voting)
#   - Physical coercion at a specific polling station (BEC/BCEV)
#   - System anomalies (duplicate ballot injection)
#
# Integrates into the existing 5-second broadcast loop without
# adding DB queries — all counters are Redis-native (O(1)).
#
# Usage:
#   VelocityMonitorService.record_vote!(election_id, department_code: "OU")
#   VelocityMonitorService.snapshot(election_id)
#   VelocityMonitorService.alerts(election_id)
#
module Election
  class VelocityMonitorService
    # A spike is flagged when a window exceeds this many standard
    # deviations above the rolling average.
    SPIKE_THRESHOLD_SIGMA = 3.0

    # Minimum votes before we start flagging (avoid false positives
    # in the first minutes when averages are unstable)
    MIN_VOTES_FOR_ALERT = 50

    # How many 5-second windows to retain for rolling average
    WINDOW_COUNT = 120  # 10 minutes of history

    # Redis key prefixes
    GLOBAL_WINDOW  = "election:velocity:global:"
    DEPT_WINDOW    = "election:velocity:dept:"
    ALERT_LIST     = "election:velocity:alerts:"
    WINDOW_HISTORY = "election:velocity:history:"

    # ── Record a vote (called at cast time) ─────────────────────

    def self.record_vote!(election_id, department_code: nil)
      window_key = current_window_key
      global_key = "#{GLOBAL_WINDOW}#{election_id}:#{window_key}"

      # Increment global counter for this 5-second window
      $redis.multi do |r|
        r.incr(global_key)
        r.expire(global_key, 15.minutes.to_i)
      end

      # Increment department counter if provided
      if department_code.present?
        dept_key = "#{DEPT_WINDOW}#{election_id}:#{department_code}:#{window_key}"
        $redis.multi do |r|
          r.incr(dept_key)
          r.expire(dept_key, 15.minutes.to_i)
        end
      end
    end

    # ── Snapshot (called every 5 seconds by BroadcastElectionTallyJob) ──

    def self.snapshot(election_id)
      window_key = current_window_key
      prev_key = previous_window_key

      current_rate = $redis.get("#{GLOBAL_WINDOW}#{election_id}:#{window_key}").to_i
      prev_rate = $redis.get("#{GLOBAL_WINDOW}#{election_id}:#{prev_key}").to_i

      # Store current rate in history for rolling average
      history_key = "#{WINDOW_HISTORY}#{election_id}"
      $redis.multi do |r|
        r.lpush(history_key, current_rate)
        r.ltrim(history_key, 0, WINDOW_COUNT - 1)
        r.expire(history_key, 1.hour.to_i)
      end

      # Compute rolling stats
      history = $redis.lrange(history_key, 0, WINDOW_COUNT - 1).map(&:to_i)
      avg = history.empty? ? 0.0 : history.sum.to_f / history.size
      stddev = compute_stddev(history, avg)

      # Votes per second (current window is 5 seconds)
      votes_per_second = current_rate / 5.0

      {
        votes_per_second: votes_per_second.round(1),
        current_window_votes: current_rate,
        previous_window_votes: prev_rate,
        rolling_average: avg.round(1),
        rolling_stddev: stddev.round(1),
        trend: trend_direction(current_rate, prev_rate),
        spike_detected: spike?(current_rate, avg, stddev, history.sum),
        window_key: window_key
      }
    end

    # ── Department-level velocity (for geographic anomaly detection) ──

    def self.department_velocity(election_id, department_code)
      window_key = current_window_key
      rate = $redis.get("#{DEPT_WINDOW}#{election_id}:#{department_code}:#{window_key}").to_i

      { department: department_code, votes_this_window: rate, votes_per_second: (rate / 5.0).round(1) }
    end

    # ── Active alerts ───────────────────────────────────────────

    def self.alerts(election_id)
      raw = $redis.lrange("#{ALERT_LIST}#{election_id}", 0, 49)
      raw.map { |a| JSON.parse(a, symbolize_names: true) }
    rescue
      []
    end

    # ── Spike detection + alert creation ────────────────────────

    def self.check_and_alert!(election_id)
      snap = snapshot(election_id)
      return unless snap[:spike_detected]

      alert = {
        type: "velocity_spike",
        votes_per_second: snap[:votes_per_second],
        rolling_average: snap[:rolling_average],
        deviation: snap[:rolling_stddev] > 0 ? ((snap[:current_window_votes] - snap[:rolling_average]) / snap[:rolling_stddev]).round(1) : 0,
        window: snap[:window_key],
        detected_at: Time.current.iso8601,
        severity: snap[:votes_per_second] > snap[:rolling_average] * 5 ? "critical" : "warning"
      }

      # Persist alert in Redis list (capped at 50)
      $redis.multi do |r|
        r.lpush("#{ALERT_LIST}#{election_id}", alert.to_json)
        r.ltrim("#{ALERT_LIST}#{election_id}", 0, 49)
        r.expire("#{ALERT_LIST}#{election_id}", 24.hours.to_i)
      end

      # Broadcast to CEP dashboard
      ActionCable.server.broadcast(
        "election_tally_#{election_id}",
        { type: "velocity_alert", alert: alert }
      )

      Rails.logger.warn(
        "[VelocityMonitor] SPIKE detected for election #{election_id}: " \
        "#{snap[:votes_per_second]} votes/sec (avg: #{snap[:rolling_average]})"
      )

      alert
    end

    # ── Reset (for testing or election start) ───────────────────

    def self.reset!(election_id)
      keys = $redis.keys("election:velocity:*#{election_id}*")
      $redis.del(*keys) if keys.any?
    end

    private

    # 5-second window key based on epoch time
    def self.current_window_key
      (Time.current.to_i / 5).to_s
    end

    def self.previous_window_key
      ((Time.current.to_i / 5) - 1).to_s
    end

    def self.compute_stddev(values, avg)
      return 0.0 if values.size < 2
      variance = values.sum { |v| (v - avg)**2 } / values.size.to_f
      Math.sqrt(variance)
    end

    def self.spike?(current, avg, stddev, total_votes)
      return false if total_votes < MIN_VOTES_FOR_ALERT
      return false if stddev.zero?
      (current - avg) > (SPIKE_THRESHOLD_SIGMA * stddev)
    end

    def self.trend_direction(current, previous)
      return "stable" if current == previous
      current > previous ? "rising" : "falling"
    end
  end
end
