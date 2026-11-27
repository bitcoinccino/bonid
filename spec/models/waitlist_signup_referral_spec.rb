# frozen_string_literal: true

require "rails_helper"

RSpec.describe WaitlistSignup, "referrals" do
  let!(:ambassador) { described_class.create!(email: "amb@example.com", first_name: "Rose", signup_type: "citizen") }

  def join(email, code)
    described_class.create!(email: email, signup_type: "citizen", referred_by_code: code)
  end

  it "records the referrer from their code, however it was typed" do
    friend = join("friend@example.com", ambassador.referral_code.downcase)
    expect(friend.referred_by_code).to eq(ambassador.referral_code)
    expect(friend.referrer).to eq(ambassador)
    expect(ambassador.referrals).to contain_exactly(friend)
  end

  it "drops an unknown code without blocking the signup" do
    expect(join("friend@example.com", "XX-NOPE00").referred_by_code).to be_nil
  end

  it "ignores a code that belongs to the same person" do
    s = described_class.new(email: "amb@example.com ", signup_type: "citizen", referred_by_code: ambassador.referral_code)
    s.valid?
    expect(s.referred_by_code).to be_nil
  end

  it "counts and sorts referrers" do
    quiet = described_class.create!(email: "quiet@example.com", signup_type: "citizen")
    3.times { |i| join("f#{i}@example.com", ambassador.referral_code) }
    join("q@example.com", quiet.referral_code)

    ranked = described_class.with_referrals_count.top_referrers_first.first(2)
    expect(ranked.map(&:email)).to eq(%w[amb@example.com quiet@example.com])
    expect(ranked.first.referrals_count).to eq(3)
    expect(described_class.min_referrals(3)).to contain_exactly(ambassador)
  end
end
