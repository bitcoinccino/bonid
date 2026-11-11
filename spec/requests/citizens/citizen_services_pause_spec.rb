# frozen_string_literal: true

require "rails_helper"

# Sèvis / Aplikasyon Mwen are paused for the v1 launch
# (CitizenServicesPausable, CITIZEN_SERVICES_ENABLED).
RSpec.describe "Citizen services pause", type: :request do
  let(:citizen) { create(:user, :with_address, :identity_verified) }

  before { sign_in citizen }

  around do |example|
    original = ENV["CITIZEN_SERVICES_ENABLED"]
    example.run
  ensure
    original.nil? ? ENV.delete("CITIZEN_SERVICES_ENABLED") : ENV["CITIZEN_SERVICES_ENABLED"] = original
  end

  context "while paused (default)" do
    before { ENV.delete("CITIZEN_SERVICES_ENABLED") }

    it "sends Sèvis back to the dashboard with a coming-soon notice" do
      get "/citizens/services"
      expect(URI(response.location).path).to eq("/citizens/dashboard")
      expect(flash[:alert]).to be_present
    end

    it "sends Aplikasyon Mwen back to the dashboard" do
      get "/citizens/service_applications"
      expect(URI(response.location).path).to eq("/citizens/dashboard")
    end

    it "hides both links from the citizen menu" do
      get "/citizens/dashboard"
      expect(response.body).not_to include(%(href="/citizens/services))
      expect(response.body).not_to include(%(href="/citizens/service_applications))
    end
  end

  context "when switched on" do
    before { ENV["CITIZEN_SERVICES_ENABLED"] = "true" }

    it "opens Sèvis and shows the links again" do
      get "/citizens/services"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/citizens/service_applications))
    end
  end
end

RSpec.describe "Citizen sidebar: Konsantman link", type: :request do
  let(:citizen) { create(:user, :with_address, :identity_verified) }
  before { sign_in citizen }

  it "links to the transaction consents page" do
    get "/citizens/dashboard"
    expect(response.body).to include(%(href="/citizens/transaction_consents))
    expect(response.body).to include("Konsantman")
  end

  it "shows how many requests are waiting" do
    partner = create(:partner, :approved)
    2.times { TransactionConsent.create!(citizen: citizen, partner: partner, transaction_type: "kyc_check", scopes: %w[profile]) }
    get "/citizens/dashboard"
    expect(response.body).to match(%r{Konsantman</span>\s*<span class="badge[^"]*">2</span>})
  end
end
