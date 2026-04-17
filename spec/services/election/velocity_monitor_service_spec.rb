# frozen_string_literal: true

require "rails_helper"

RSpec.describe Election::VelocityMonitorService do
  let(:election_id) { 42 }
  let(:redis) { instance_double(Redis) }

  before do
    @original_redis = $redis
    $redis = redis
    allow(redis).to receive(:multi).and_yield(redis)
    allow(redis).to receive(:incr).and_return(1)
    allow(redis).to receive(:expire).and_return(true)
    allow(redis).to receive(:get).and_return("0")
    allow(redis).to receive(:lrange).and_return([])
    allow(redis).to receive(:lpush).and_return(1)
    allow(redis).to receive(:ltrim).and_return("OK")
    allow(redis).to receive(:keys).and_return([])
    allow(redis).to receive(:del)
  end

  after do
    $redis = @original_redis
  end

  # ─────────────────────────────────────────────────────────
  # .record_vote!
  # ─────────────────────────────────────────────────────────
  describe ".record_vote!" do
    it "increments the global window counter" do
      expect(redis).to receive(:incr).with(/election:velocity:global:#{election_id}/)
      described_class.record_vote!(election_id)
    end

    it "increments the department counter when provided" do
      expect(redis).to receive(:incr).with(/election:velocity:dept:#{election_id}:OU/)
      described_class.record_vote!(election_id, department_code: "OU")
    end

    it "skips department counter when not provided" do
      expect(redis).not_to receive(:incr).with(/election:velocity:dept/)
      described_class.record_vote!(election_id)
    end
  end

  # ─────────────────────────────────────────────────────────
  # .snapshot
  # ─────────────────────────────────────────────────────────
  describe ".snapshot" do
    it "returns velocity metrics" do
      allow(redis).to receive(:get).and_return("10")
      allow(redis).to receive(:lrange).and_return([ "8", "10", "12", "9", "11" ])

      snap = described_class.snapshot(election_id)

      expect(snap).to include(:votes_per_second, :current_window_votes, :rolling_average, :trend, :spike_detected)
      expect(snap[:votes_per_second]).to eq(2.0) # 10 votes / 5 seconds
      expect(snap[:current_window_votes]).to eq(10)
    end

    it "detects rising trend" do
      allow(redis).to receive(:get).with(/global.*#{election_id}/).and_return("20", "10")
      allow(redis).to receive(:lrange).and_return([ "15", "10", "8" ])

      snap = described_class.snapshot(election_id)
      expect(snap[:trend]).to eq("rising")
    end

    it "detects falling trend" do
      allow(redis).to receive(:get).with(/global.*#{election_id}/).and_return("5", "15")
      allow(redis).to receive(:lrange).and_return([ "10", "15", "12" ])

      snap = described_class.snapshot(election_id)
      expect(snap[:trend]).to eq("falling")
    end
  end

  # ─────────────────────────────────────────────────────────
  # .check_and_alert!
  # ─────────────────────────────────────────────────────────
  describe ".check_and_alert!" do
    it "does not alert when below threshold" do
      allow(redis).to receive(:get).and_return("5")
      allow(redis).to receive(:lrange).and_return([ "4", "5", "6", "4", "5" ])

      expect(ActionCable.server).not_to receive(:broadcast)
      result = described_class.check_and_alert!(election_id)
      expect(result).to be_nil
    end

    it "fires alert on velocity spike" do
      # Simulate a massive spike: 100 votes in a window where avg is 5
      allow(redis).to receive(:get).and_return("100", "5")
      allow(redis).to receive(:lrange).and_return(
        ([ "5" ] * 50) + [ "100" ] # 50 windows of 5 + current spike, total > MIN_VOTES
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        "election_tally_#{election_id}",
        hash_including(type: "velocity_alert")
      )

      alert = described_class.check_and_alert!(election_id)
      expect(alert).to be_present
      expect(alert[:type]).to eq("velocity_spike")
    end

    it "skips alert when total votes below minimum" do
      # Spike but too few total votes (early election)
      allow(redis).to receive(:get).and_return("10", "0")
      allow(redis).to receive(:lrange).and_return([ "0", "0", "10" ]) # total = 10 < MIN_VOTES

      result = described_class.check_and_alert!(election_id)
      expect(result).to be_nil
    end
  end

  # ─────────────────────────────────────────────────────────
  # .department_velocity
  # ─────────────────────────────────────────────────────────
  describe ".department_velocity" do
    it "returns department-specific rate" do
      allow(redis).to receive(:get).with(/dept:#{election_id}:OU/).and_return("15")

      result = described_class.department_velocity(election_id, "OU")

      expect(result[:department]).to eq("OU")
      expect(result[:votes_this_window]).to eq(15)
      expect(result[:votes_per_second]).to eq(3.0)
    end
  end

  # ─────────────────────────────────────────────────────────
  # .reset!
  # ─────────────────────────────────────────────────────────
  describe ".reset!" do
    it "deletes all velocity keys for the election" do
      allow(redis).to receive(:keys).and_return([ "key1", "key2" ])
      expect(redis).to receive(:del).with("key1", "key2")

      described_class.reset!(election_id)
    end
  end
end
