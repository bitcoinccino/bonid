require 'rails_helper'

RSpec.describe "Api::V1::Verifications", type: :request do
  let(:partner) do
    Partner.create!(
      name: "BonID Test Partner",
      verified_at: Time.current,
      active: true,
      api_key_digest: BCrypt::Password.create("test_api_key")
    )
  end

  let(:headers) do
    {
      "X-Partner-Api-Key" => "test_api_key",
      "Content-Type" => "application/json"
    }
  end

  let(:valid_params) do
    {
      data: {
        bonid: "HT123456789",
        type: "kyc"
      }
    }
  end

  before do
    # Mock non-auth parts (cache, logs, URLs – let headers auth naturally)
    allow(Rails.cache).to receive(:read).and_return(0)
    allow(Rails.cache).to receive(:write).and_return(true)
    allow(ApiAccessLog).to receive(:create!).and_return(true)
    allow_any_instance_of(Api::V1::VerificationsController).to receive(:rails_blob_url).and_return("https://example.com/selfie.jpg")
  end

  describe "POST /api/v1/verify_identity" do
    let(:json_response) { JSON.parse(response.body) }

    context "when BonID is verified" do
      let(:bonid) { "MO-1968-M-OUEST-P-1001" }
      let!(:user) { create(:user, :with_address, bonid: bonid) }
      let!(:verified_submission) do
        IdentitySubmission.create!(
          user: user,
          partner: partner,
          bonid: bonid,
          status: :approved,
          verified_at: Time.current,
          id_type: "cin"
        )
      end

      it "returns 200 OK with verified data" do
        post "/api/v1/verify_identity", params: { bonid: bonid }, headers: headers
        expect(response).to have_http_status(:ok)
        expect(json_response["status"]).to eq("verified")
        expect(json_response["citizen"]).to include("first_name", "last_name")
      end
    end

    context "when BonID exists but is not verified" do
      let!(:user) { create(:user, :with_address, bonid: "MO-1968-M-OUEST-P-2002") }

      before do
        IdentitySubmission.create!(
          user: user,
          partner: partner,
          bonid: user.bonid,
          status: :pending,
          id_type: "cin"
        )
      end

      it "returns 404 not_verified" do
        post "/api/v1/verify_identity", params: { bonid: user.bonid }, headers: headers
        expect(response).to have_http_status(:not_found)
        expect(json_response["status"]).to eq("not_verified")
      end
    end

    context "when BonID is invalid" do
      it "returns 404 not_verified for invalid BonID" do
        post "/api/v1/verify_identity", params: { bonid: "INVALID-BONID" }, headers: headers
        expect(response).to have_http_status(:not_found)
        expect(json_response["status"]).to eq("not_verified")
      end
    end

    context "with invalid API key" do
      let(:headers) { { "X-Partner-Api-Key" => "invalid_key", "Content-Type" => "application/json" } }

      it "returns 401" do
        post "/api/v1/verify_identity", params: { bonid: "MO-1968-M-OUEST-P-1001" }, headers: headers
        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("Invalid API key")
      end
    end
  end

  describe "POST /api/v1/verifications" do
    let(:json_response) { JSON.parse(response.body) }

    context "with valid API key and sufficient credits" do
      before do
        partner.update!(credit_balance: 10_000)
      end

      it "creates verification, deducts credits, returns success" do
        expect {
          post "/api/v1/verifications", params: valid_params.to_json, headers: headers
        }.to change(VerificationRecord, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json_response["status"]).to eq("success")
      end
    end

    context "with valid API key but insufficient credits" do
      before do
        partner.update!(credit_balance: 0)
      end

      it "returns 402, no new record" do
        expect {
          post "/api/v1/verifications", params: valid_params.to_json, headers: headers
        }.not_to change(VerificationRecord, :count)

        expect(response).to have_http_status(:payment_required)
      end
    end

    context "with invalid API key" do
      let(:headers) { { "Authorization" => "Bearer invalid_key", "Content-Type" => "application/json" } }

      it "returns 401" do
        post "/api/v1/verifications", params: valid_params.to_json, headers: headers

        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("Invalid API key")
      end
    end

    context "with missing bonid" do
      let(:valid_params) do
        {
          data: {
            type: "kyc"
          }
        }
      end

      it "returns 400" do
        post "/api/v1/verifications", params: valid_params.to_json, headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(json_response["error"]).to eq("Missing bonid")
      end
    end

    context "with invalid data type" do
      let(:valid_params) do
        {
          data: {
            bonid: "HT123456789",
            type: "invalid_type"
          }
        }
      end

      it "returns 400" do
        post "/api/v1/verifications", params: valid_params.to_json, headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(json_response["error"]).to eq("Invalid verification type")
      end
    end
  end
end
# # frozen_string_literal: true

# require "rails_helper"

# RSpec.describe "Api::V1::Verifications", type: :request do
#   let!(:partner) do
#     Partner.create!(
#       name: "BonID Test Partner",
#       verified_at: Time.current,
#       active: true,
#       api_key_digest: BCrypt::Password.create("test_api_key")
#     )
#   end

#   let(:headers) do
#     {
#       "X-Partner-Api-Key" => "test_api_key",
#       "Content-Type" => "application/json"
#     }
#   end

#   before do
#     allow_any_instance_of(Api::V1::VerificationsController)
#       .to receive(:authenticate_api_key!)
#       .and_return(true)

#     allow_any_instance_of(Api::V1::VerificationsController)
#       .to receive(:instance_variable_get)
#       .with(:@current_partner)
#       .and_return(partner)

#     allow(Rails.cache).to receive(:read).and_return(0)
#     allow(Rails.cache).to receive(:write).and_return(true)
#     allow(ApiAccessLog).to receive(:create!).and_return(true)
#     allow_any_instance_of(Api::V1::VerificationsController)
#       .to receive(:rails_blob_url)
#       .and_return("https://example.com/selfie.jpg")
#   end

#   describe "POST /api/v1/verify_identity" do
#     let(:json_response) { JSON.parse(response.body) }

#     context "when BonID is verified" do
#       let(:bonid) { "MO-1968-M-OUEST-P-1001" }
#       let!(:user) { create(:user, :with_address, bonid: bonid) }
#       let!(:verified_submission) do
#         IdentitySubmission.create!(
#           user: user,
#           partner: partner,
#           bonid: bonid,
#           status: :approved,
#           verified_at: Time.current,
#           id_type: "cin"
#         )
#       end

#       it "returns 200 OK with verified data" do
#         post "/api/v1/verify_identity", params: { bonid: bonid }, headers: headers
#         expect(response).to have_http_status(:ok)
#         expect(json_response["status"]).to eq("verified")
#         expect(json_response["citizen"]).to include("first_name", "last_name")
#       end
#     end

#     context "when BonID exists but is not verified" do
#       let!(:user) { create(:user, :with_address, bonid: "MO-1968-M-OUEST-P-2002") }

#       before do
#         IdentitySubmission.create!(
#           user: user,
#           partner: partner,
#           bonid: user.bonid,
#           status: :pending,
#           id_type: "cin"
#         )
#       end

#       it "returns 404 not_verified" do
#         post "/api/v1/verify_identity", params: { bonid: user.bonid }, headers: headers
#         expect(response).to have_http_status(:not_found)
#         expect(json_response["status"]).to eq("not_verified")
#       end
#     end

#     context "when BonID is invalid" do
#       it "returns 404 not_verified for invalid BonID" do
#         post "/api/v1/verify_identity", params: { bonid: "INVALID-BONID" }, headers: headers
#         expect(response).to have_http_status(:not_found)
#         expect(json_response["status"]).to eq("not_verified")
#       end
#     end
#   end
# end
