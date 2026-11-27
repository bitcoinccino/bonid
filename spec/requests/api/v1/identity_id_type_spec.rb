# frozen_string_literal: true

require "rails_helper"

# id_type is the document the identity was verified with ("cin" or
# "passport"), not the product. The holder kind moved to holder_type.
RSpec.describe "Api::V1::Identity id_type", type: :request, real_auth: true do
  let!(:partner)    { create(:partner, :approved, raw_api_key: "test_api_key") }
  let!(:citizen)    { create(:user, :with_address, bonid: "BZ-1970-M-ND-P2334-0B6") }
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  it "reports the document on the status endpoint" do
    get "/api/v1/identity/#{citizen.bonid}/status", headers: { "X-Partner-Api-Key" => "test_api_key" }
    expect(response).to have_http_status(:ok)
    verification = JSON.parse(response.body)["verification"]
    expect(verification).to include("found" => true, "id_type" => "cin", "status" => "verified")
  end

  it "reports passport when that was the document" do
    submission.update_columns(id_type: "passport")
    get "/api/v1/identity/#{citizen.bonid}/status", headers: { "X-Partner-Api-Key" => "test_api_key" }
    expect(JSON.parse(response.body).dig("verification", "id_type")).to eq("passport")
  end

  it "uses cin/passport in the identity response and moves the holder kind to holder_type" do
    token = OauthAccessToken.create!(partner: partner, citizen: citizen, scopes: %w[identity:verify profile], expires_at: 1.hour.from_now)
    get "/api/v1/identity/#{citizen.bonid}", headers: { "Authorization" => "Bearer #{token.token}" }
    body = JSON.parse(response.body)
    expect(body).to include("id_type" => "cin", "holder_type" => "citizen")
    expect(body.dig("identity", "id_type")).to eq("cin")
  end
end
