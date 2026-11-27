# frozen_string_literal: true

require "rails_helper"

RSpec.describe WaitlistSignup, ".convert_for!" do
  it "marks the matching waitlist entry converted, ignoring case and spaces" do
    signup = described_class.create!(email: "jean@example.com", signup_type: "citizen")
    expect(described_class.convert_for!("  Jean@Example.com ")).to eq(1)
    expect(signup.reload.status).to eq("converted")
    expect(signup.converted_at).to be_present
  end

  it "leaves already-converted entries and blank emails alone" do
    described_class.create!(email: "a@example.com", signup_type: "citizen", status: "converted", converted_at: 1.day.ago)
    expect(described_class.convert_for!("a@example.com")).to eq(0)
    expect(described_class.convert_for!(nil)).to eq(0)
  end
end
