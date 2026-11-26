# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin waitlist: referrals", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    sign_in create(:admin_user), scope: :admin_user
    allow_any_instance_of(Admin::WaitlistSignupsController).to receive(:ensure_guidelines_confirmed).and_return(true)

    amb = WaitlistSignup.create!(email: "amb@example.com", signup_type: "citizen")
    WaitlistSignup.create!(email: "solo@example.com", signup_type: "citizen")
    3.times { |i| WaitlistSignup.create!(email: "f#{i}@example.com", signup_type: "citizen", referred_by_code: amb.referral_code) }
  end

  it "shows only 3+ referrers with their count" do
    get admin_waitlist_signups_path(referrals: "3")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("amb@example.com")
    expect(response.body).not_to include("solo@example.com", "f0@example.com")
  end

  it "lists top referrers first" do
    get admin_waitlist_signups_path(referrals: "top")
    expect(response.body.index("amb@example.com")).to be < response.body.index("solo@example.com")
  end

  it "shows who referred each person" do
    get admin_waitlist_signups_path
    expect(response.body).to include("via <code>#{WaitlistSignup.find_by(email: 'amb@example.com').referral_code}</code>")
  end
end
