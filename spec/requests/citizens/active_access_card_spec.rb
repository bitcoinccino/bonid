# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Aksè aktif card", type: :request do
  # These examples assert the English copy; the portal renders in the
  # citizen's saved language (Kreyòl by default).
  let(:citizen) { create(:user, :with_address, :identity_verified, preferred_locale: "en") }
  let(:partner) { create(:partner, :approved, name: "Zèllus", sector: "fintech") }
  let!(:grant) do
    ConsentGrant.create!(
      citizen: citizen, partner: partner, status: :approved,
      requested_scopes: %w[openid profile email phone address identity:verify],
      granted_scopes:   %w[openid profile email phone address identity:verify],
      granted_at: 10.days.ago, expires_at: Time.zone.local(2027, 2, 6),
      last_accessed_at: 1.day.ago, access_count: 55
    )
  end

  before { sign_in citizen }

  it "describes the access in plain English" do
    get "/citizens/consents"
    body = response.body
    expect(body).to include("Has access")
    expect(body).to include("What Zèllus can see")
    expect(body).to include("Name, date of birth and photo")
    expect(body).to include("Photo and face check")
    expect(body).to include("Home address")
    expect(body).to include("Last looked at your information")
    expect(body).to include("55 times")
    expect(body).to include("Access ends on Feb 6, 2027")
    expect(body).not_to include("Identity:Verify")
    expect(body).not_to include("Openid")
    expect(body).not_to include("Access Count")
  end

  it "puts Remove access at the bottom of the card with a clear confirmation, not in a menu" do
    get "/citizens/consents"
    expect(response.body).to include("Remove access")
    expect(CGI.unescapeHTML(response.body)).to include("Remove Zèllus's access?")
    expect(response.body).to include("delete the information they already have within 30 days")
    expect(response.body).not_to include("consent-kebab-btn")
  end

  it "removes access and shows when it happened" do
    delete "/citizens/consents/#{grant.id}", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(grant.reload).to be_revoked
    expect(response.body).to include("can no longer see your information")
    expect(response.body).to include("You removed access on")
  end
end
