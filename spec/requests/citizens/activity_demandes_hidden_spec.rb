# frozen_string_literal: true

require "rails_helper"

# The Demandes (applications) tab follows the partner-services switch
# (CITIZEN_SERVICES_ENABLED): hidden while services are paused.
RSpec.describe "Citizens::Activity — Demandes tab", type: :request do
  include Devise::Test::IntegrationHelpers

  before(:all) { Devise.mappings[:user] = Devise.mappings[:citizen] }

  let!(:citizen) { create(:user, :with_address) }

  before { sign_in citizen, scope: :citizen }

  around do |example|
    original = ENV["CITIZEN_SERVICES_ENABLED"]
    example.run
  ensure
    original.nil? ? ENV.delete("CITIZEN_SERVICES_ENABLED") : ENV["CITIZEN_SERVICES_ENABLED"] = original
  end

  context "while services are paused (default)" do
    before { ENV.delete("CITIZEN_SERVICES_ENABLED") }

    it "has no Demandes tab" do
      get citizens_activity_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("tab=scans")
      expect(response.body).not_to include("tab=applications")
    end

    it "falls back to the All tab when asked for applications" do
      get citizens_activity_path(tab: "applications")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("tab=applications")
    end
  end

  context "when services are on" do
    before { ENV["CITIZEN_SERVICES_ENABLED"] = "true" }

    it "shows the Demandes tab" do
      get citizens_activity_path
      expect(response.body).to include("tab=applications")
    end
  end
end
