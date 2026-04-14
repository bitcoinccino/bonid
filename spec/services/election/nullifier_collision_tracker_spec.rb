# frozen_string_literal: true

require "rails_helper"

RSpec.describe Election::NullifierCollisionTracker do
  let(:election_id) { 42 }
  let(:nullifier) { "abc123def456" }
  let(:ip) { "198.51.100.42" }
  let(:redis) { instance_double(Redis) }

  before do
    @original_redis = $redis
    $redis = redis
    allow(redis).to receive(:multi).and_yield(redis)
    allow(redis).to receive(:incr).and_return(1)
    allow(redis).to receive(:expire).and_return(true)
    allow(redis).to receive(:lpush).and_return(1)
    allow(redis).to receive(:ltrim).and_return("OK")
    allow(redis).to receive(:lrange).and_return([])
    allow(redis).to receive(:keys).and_return([])
    allow(redis).to receive(:del)
  end

  after do
    $redis = @original_redis
  end

  # ─────────────────────────────────────────────────────────
  # .record!
  # ─────────────────────────────────────────────────────────
  describe ".record!" do
    it "tracks collision for a nullifier" do
      expect(redis).to receive(:incr).with(/nullifier_collision:count:#{election_id}:#{nullifier}/)

      event = described_class.record!(election_id, nullifier: nullifier)

      expect(event[:nullifier_prefix]).to eq(nullifier[0..7])
      expect(event[:collision_number]).to eq(1)
    end

    it "tracks collisions per IP when provided" do
      expect(redis).to receive(:incr).with(/nullifier_collision:ip:#{election_id}:#{ip}/)

      described_class.record!(election_id, nullifier: nullifier, ip_address: ip)
    end

    it "hashes IP for privacy in the log" do
      event = described_class.record!(election_id, nullifier: nullifier, ip_address: ip)

      # IP is SHA-256 hashed and truncated, not stored in plaintext
      expect(event[:ip_hash]).not_to eq(ip)
      expect(event[:ip_hash].length).to eq(12) # first 12 chars of hash
    end

    it "records channel and department_code" do
      event = described_class.record!(
        election_id,
        nullifier: nullifier,
        channel: "consulate",
        department_code: "US"
      )

      expect(event[:channel]).to eq("consulate")
      expect(event[:department_code]).to eq("US")
    end
  end

  # ─────────────────────────────────────────────────────────
  # Alert thresholds
  # ─────────────────────────────────────────────────────────
  describe "alert thresholds" do
    it "fires warning when nullifier hits SUSPICIOUS_THRESHOLD" do
      allow(redis).to receive(:incr).and_return(
        described_class::SUSPICIOUS_THRESHOLD, # nullifier count
        1 # IP count
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        "election_tally_#{election_id}",
        hash_including(type: "nullifier_collision_alert")
      )

      event = described_class.record!(election_id, nullifier: nullifier, ip_address: ip)
      # Alert was broadcast
    end

    it "fires critical alert when IP hits CRITICAL_THRESHOLD" do
      allow(redis).to receive(:incr).and_return(
        1,  # nullifier count (below suspicious)
        described_class::CRITICAL_THRESHOLD # IP count at threshold
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        "election_tally_#{election_id}",
        hash_including(type: "nullifier_collision_alert")
      )

      described_class.record!(election_id, nullifier: nullifier, ip_address: ip)
    end

    it "does not alert below thresholds" do
      allow(redis).to receive(:incr).and_return(1, 1)

      expect(ActionCable.server).not_to receive(:broadcast)

      described_class.record!(election_id, nullifier: nullifier, ip_address: ip)
    end
  end

  # ─────────────────────────────────────────────────────────
  # .stats
  # ─────────────────────────────────────────────────────────
  describe ".stats" do
    it "returns empty stats when no collisions" do
      stats = described_class.stats(election_id)

      expect(stats[:total_collisions]).to eq(0)
      expect(stats[:unique_nullifiers_involved]).to eq(0)
      expect(stats[:suspicious_count]).to eq(0)
      expect(stats[:critical_count]).to eq(0)
    end

    it "computes stats from collision log" do
      log_entries = [
        { nullifier_prefix: "abc12345", collision_number: 3, ip_hash: "aaa", ip_total_collisions: 1, channel: "remote", timestamp: Time.current.iso8601 }.to_json,
        { nullifier_prefix: "abc12345", collision_number: 4, ip_hash: "bbb", ip_total_collisions: 1, channel: "remote", timestamp: Time.current.iso8601 }.to_json,
        { nullifier_prefix: "def67890", collision_number: 1, ip_hash: "aaa", ip_total_collisions: 2, channel: "consulate", timestamp: Time.current.iso8601 }.to_json
      ]
      allow(redis).to receive(:lrange).and_return(log_entries)

      stats = described_class.stats(election_id)

      expect(stats[:total_collisions]).to eq(3)
      expect(stats[:unique_nullifiers_involved]).to eq(2)
      expect(stats[:unique_ips_involved]).to eq(2)
      expect(stats[:suspicious_count]).to eq(2) # collision_number >= 3
      expect(stats[:by_channel]).to eq({ "remote" => 2, "consulate" => 1 })
    end
  end

  # ─────────────────────────────────────────────────────────
  # .recent_log
  # ─────────────────────────────────────────────────────────
  describe ".recent_log" do
    it "returns capped recent entries" do
      entries = 5.times.map do |i|
        { nullifier_prefix: "abc#{i}", collision_number: 1, timestamp: Time.current.iso8601 }.to_json
      end
      allow(redis).to receive(:lrange).and_return(entries)

      log = described_class.recent_log(election_id, limit: 3)

      expect(log.size).to eq(3)
    end
  end

  # ─────────────────────────────────────────────────────────
  # .reset!
  # ─────────────────────────────────────────────────────────
  describe ".reset!" do
    it "clears all collision keys" do
      allow(redis).to receive(:keys).and_return(["k1", "k2"])
      expect(redis).to receive(:del).with("k1", "k2")

      described_class.reset!(election_id)
    end
  end
end
