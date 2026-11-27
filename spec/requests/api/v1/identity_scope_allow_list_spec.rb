# frozen_string_literal: true

require "rails_helper"

# The identity response is an allow-list: a partner only ever receives the
# identity keys its scopes map to (SCOPE_IDENTITY_FIELDS). Regression for the
# old deny-list, which let OAuth tokens receive NIF, place of birth, family
# members and the QR code without the tax/civil scopes.
RSpec.describe "Api::V1::Identity scope allow-list", type: :request, real_auth: true do
  let!(:partner)    { create(:partner, :approved, raw_api_key: "test_api_key") }
  let!(:citizen)    { create(:user, :with_address, bonid: "BZ-1970-M-ND-P2334-0B6") }
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  def fetch_with_token(scopes)
    token = OauthAccessToken.create!(partner: partner, citizen: citizen, scopes: scopes, expires_at: 1.hour.from_now)
    get "/api/v1/identity/#{citizen.bonid}", headers: { "Authorization" => "Bearer #{token.token}" }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)["identity"]
  end

  let(:restricted_keys) do
    %w[nif matricule_fiscale tax_id place_of_birth family_members birth_certificate_ref
       blood_type allergies medications height weight emergency_contacts social_handles
       email phone address postal_code]
  end

  it "gives an OAuth token only the fields its scopes allow" do
    identity = fetch_with_token(%w[identity:verify profile])

    expect(identity.keys & restricted_keys).to be_empty
    expect(identity).not_to have_key("qr_code")
    expect(identity).to include("bonid", "verification", "full_name", "photo_url", "biometrics")
  end

  it "never sends a key that is not mapped to a scope" do
    identity = fetch_with_token(%w[identity:verify profile])
    allowed = Api::V1::IdentityController.new.send(:allowed_identity_fields, %w[identity:verify profile]).map(&:to_s)

    expect(identity.keys - allowed).to be_empty
  end

  it "sends every mapped field for identity:details, but still no QR code" do
    # The base scope gate requires identity:verify to call /identity at all.
    identity = fetch_with_token(%w[identity:verify identity:details])

    expect(identity).to include("full_name", "address", "postal_code", "family_members", "emergency_contacts")
    expect(identity).not_to have_key("qr_code")
  end
end
