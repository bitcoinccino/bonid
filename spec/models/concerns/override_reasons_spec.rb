# frozen_string_literal: true

require "rails_helper"

RSpec.describe OverrideReasons do
  describe "REASONS" do
    it "contains all expected override keys" do
      expect(OverrideReasons::REASONS.keys).to contain_exactly(
        "false_positive_twins",
        "false_positive_quality",
        "verified_in_person",
        "reissue_legitimate",
        "different_person",
        "other"
      )
    end

    it "is frozen" do
      expect(OverrideReasons::REASONS).to be_frozen
    end
  end

  describe ".options_for_select" do
    it "returns array of [label, key] pairs" do
      options = OverrideReasons.options_for_select
      expect(options).to be_an(Array)
      expect(options.length).to eq(OverrideReasons::REASONS.length)

      options.each do |label, key|
        expect(OverrideReasons::REASONS).to have_key(key)
        expect(label).to eq(OverrideReasons::REASONS[key])
      end
    end
  end

  describe ".valid?" do
    it "returns true for valid reason keys" do
      OverrideReasons::REASONS.each_key do |key|
        expect(OverrideReasons.valid?(key)).to be true
      end
    end

    it "returns false for invalid reason keys" do
      expect(OverrideReasons.valid?("made_up_reason")).to be false
      expect(OverrideReasons.valid?("")).to be false
    end

    it "handles symbol input" do
      expect(OverrideReasons.valid?(:false_positive_twins)).to be true
    end
  end

  describe ".label_for" do
    it "returns the Kreyòl label for a valid reason" do
      expect(OverrideReasons.label_for("verified_in_person")).to eq("Verifye an pèsòn — dokiman fizik konfime")
    end

    it "returns humanized string for unknown reason" do
      expect(OverrideReasons.label_for("unknown_thing")).to eq("Unknown thing")
    end
  end
end
