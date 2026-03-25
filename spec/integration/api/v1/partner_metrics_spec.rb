# frozen_string_literal: true

require "rails_helper"
require "swagger_helper"

RSpec.describe "Partner Metrics API", type: :request, swagger_doc: "openapi.yaml" do
  path "/partner/metrics" do
    get("Get partner metrics") do
      tags [ "Partners" ]
      consumes "application/json"
      produces "application/json"

      parameter name: "X-Partner-Api-Key",
                in: :header,
                type: :string,
                description: "Your Partner API key",
                required: true

      let(:partner_key) { "bonid_unibank_test_93931bd8a9c130ae" }

      let!(:partner) do
        Partner.find_by(name: "Unibank") ||
          Partner.create!(
            name: "Unibank",
            sector: "banking",
            verified_at: Time.current,
            api_key_digest: Digest::SHA256.hexdigest(partner_key)
          )
      end

      response(200, "Metrics retrieved successfully") do
        let("X-Partner-Api-Key") { partner_key }

        schema type: :object,
          properties: {
            partner: {
              type: :object,
              properties: {
                id: { type: :integer },
                name: { type: :string },
                sector: { type: :string }
              }
            },
            period: { type: :string },
            metrics: {
              type: :object,
              properties: {
                total_requests: { type: :integer },
                successful_requests: { type: :integer },
                failed_requests: { type: :integer },
                avg_latency_ms: { type: %i[number null] } # ✅ fix
              }
            },
            endpoint_breakdown: {
              type: :array,
              items: {
                type: :object,
                properties: {
                  endpoint: { type: :string },
                  requests: { type: :integer }
                }
              }
            },
            rate_limit: {
              type: :object,
              properties: {
                limit: { type: :integer },
                remaining: { type: :integer }
              }
            },
            generated_at: { type: :string }
          },
          required: [ "partner", "metrics" ]


        example "application/json", :success_example, {
          partner: {
            id: 24,
            name: "Unibank",
            sector: "banking"
          },
          period: "last_24h",
          metrics: {
            total_requests: 70,
            successful_requests: 21,
            failed_requests: 49,
            avg_latency_ms: 126.62
          },
          endpoint_breakdown: [
            { endpoint: "/api/v1/verify_identity", requests: 29 },
            { endpoint: "/api/v1/bonid_status", requests: 37 },
            { endpoint: "/api/v1/partner/metrics", requests: 4 }
          ],
          rate_limit: {
            limit: 1000,
            remaining: 930
          },
          generated_at: "2025-10-24T14:38:12-04:00"
        }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["partner"]["name"]).to eq("Unibank")
          expect(data["metrics"]).to have_key("total_requests")
        end
      end

      response(401, "Unauthorized") do
        let("X-Partner-Api-Key") { "" }

        schema type: :object,
               properties: {
                 error: { type: :string }
               },
               required: [ "error" ]

        example "application/json", :unauthorized_example, {
          error: "Invalid or inactive API key"
        }

        run_test!
      end

      response(500, "Internal server error") do
        before do
          allow(ApiAccessLog).to receive(:where).and_raise(StandardError, "Simulated internal error")
        end

        let("X-Partner-Api-Key") { partner_key }

        schema type: :object,
               properties: {
                 error: { type: :string },
                 message: { type: :string }
               },
               required: [ "error" ]

        example "application/json", :error_example, {
          error: "Internal Server Error",
          message: "Simulated internal error"
        }

        run_test!
      end
    end
  end
end
