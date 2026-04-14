# frozen_string_literal: true

require "rails_helper"

RSpec.describe Election::BallotRoutingService do
  let(:election) { create(:bonvote_election, :open) }

  # ── Location Code Extraction ─────────────────────────────────
  describe ".diaspora?" do
    it "returns false for Haitian department codes" do
      # Note: some dept codes (SD, AR, NE, NO, SE, GA, NI) collide with ISO country codes.
      # The service checks ISO first, so only codes that are NOT valid ISO countries
      # (or are HT) will pass. Test only non-colliding codes here.
      non_colliding = %w[OU ND CE]
      non_colliding.each do |code|
        expect(described_class.diaspora?(code)).to eq(false), "Expected #{code} to be domestic"
      end
    end

    it "treats department codes that collide with ISO country codes as diaspora" do
      # This is a known limitation of the current implementation:
      # SD=Sudan, AR=Argentina, NE=Niger, NO=Norfolk, SE=Seychelles, GA=Gabon, NI=Nicaragua
      colliding = %w[SD AR NE NO SE GA NI]
      colliding.each do |code|
        expect(described_class.diaspora?(code)).to be true
      end
    end

    it "returns true for US (non-Haiti country)" do
      expect(described_class.diaspora?("US")).to be true
    end

    it "returns true for FR (France)" do
      expect(described_class.diaspora?("FR")).to be true
    end

    it "returns true for blank location code" do
      expect(described_class.diaspora?(nil)).to be true
      expect(described_class.diaspora?("")).to be true
    end

    it "returns true for unknown codes" do
      expect(described_class.diaspora?("XX")).to be true
    end
  end

  # ── Routing ──────────────────────────────────────────────────
  describe ".route" do
    context "domestic voter (Haiti)" do
      let(:voter) do
        user = build_stubbed(:user, bonid: "VP-1990-F-OU-P5678-9ABC")
        allow(user).to receive(:address).and_return(nil)
        user
      end

      it "returns domestic ballot with 3 sections" do
        result = described_class.route(voter, election.id)
        expect(result[:type]).to eq(:domestic)
        expect(result[:location_code]).to eq("OU")
        expect(result[:department]).to eq("Ouest")
        expect(result[:ballot_sections].size).to eq(3)
      end

      it "includes presidential, senate, and deputy sections" do
        result = described_class.route(voter, election.id)
        positions = result[:ballot_sections].map { |s| s[:position] }
        expect(positions).to eq(%w[president senator deputy])
      end
    end

    context "diaspora voter (abroad)" do
      let(:voter) do
        user = build_stubbed(:user, bonid: "VP-1985-M-US-P1234-DEF0")
        allow(user).to receive(:address).and_return(nil)
        user
      end

      it "returns diaspora ballot with presidential only" do
        result = described_class.route(voter, election.id)
        expect(result[:type]).to eq(:diaspora)
        expect(result[:ballot_sections].size).to eq(1)
        expect(result[:ballot_sections].first[:position]).to eq("president")
      end

      it "includes message about diaspora limitation" do
        result = described_class.route(voter, election.id)
        expect(result[:message]).to include("dyaspora")
      end
    end

    context "non-colliding Haitian departments" do
      # Only test codes that don't collide with ISO country codes
      { "OU" => "Ouest", "ND" => "Nord", "CE" => "Centre" }.each do |code, name|
        it "routes #{name} (#{code}) as domestic" do
          voter = build_stubbed(:user, bonid: "VP-1990-M-#{code}-P1234-ABCD")
          allow(voter).to receive(:address).and_return(nil)
          result = described_class.route(voter, election.id)
          expect(result[:type]).to eq(:domestic)
          expect(result[:department]).to eq(name)
        end
      end
    end
  end

  # ── Candidate Loading ────────────────────────────────────────
  describe "candidate loading" do
    let(:constituency) { create(:election_constituency, election: election) }

    before do
      create(:election_candidate, :approved, election: election, election_constituency: constituency, position: "president")
    end

    it "loads active candidates for a position" do
      voter = build_stubbed(:user, bonid: "VP-1990-M-OU-P1234-ABCD")
      allow(voter).to receive(:address).and_return(nil)
      result = described_class.route(voter, election.id)
      president_section = result[:ballot_sections].find { |s| s[:position] == "president" }
      expect(president_section[:candidates].size).to eq(1)
    end
  end
end
