# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Webhooks", type: :request, real_auth: true do
  let!(:partner) { create(:partner, verified_at: Time.current, active: true, raw_api_key: "secret") }

  let(:headers) { { "X-Partner-Api-Key" => "secret", "Content-Type" => "application/json" } }


  describe "POST /api/v1/webhooks" do
    let(:payload) do
      {
        event: "bonid.status.changed",
        bonid: "HT1000-5555",
        status: "revoked",
        timestamp: Time.current.iso8601
      }
    end

    it "accepts valid webhook and stores event" do
      expect(ApiWebhookEvent).to receive(:create!).with(hash_including(:partner, :event_type, :bonid))
      post "/api/v1/webhooks", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["message"]).to eq("Webhook received")
    end

    it "rejects missing API key" do
      post "/api/v1/webhooks", params: payload.to_json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
