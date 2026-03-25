# frozen_string_literal: true

RSpec.configure do |config|
  # === OpenAPI output directory ===
  config.openapi_root = Rails.root.join("public", "api", "v1").to_s

  # === Define OpenAPI specs ===
  config.openapi_specs = {
    "openapi.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "BonID Partner API",
        version: "v1.5.0",
        description: <<~DESC
          Scalable and modular **BonID Partner API (v1.3)**.

          Verify Haitian citizens and residents via a unified identity verification API.

          ### 🔐 Authentication
          - Use `X-Partner-Api-Key` header with your issued API key.
          - Optional: `Authorization: Bearer <HMAC-SHA256 signature>` for advanced partners.

          ### 🌍 Environments
          - **Production:** https://api.bonid.ht/api/v1#{'  '}
          - **Sandbox:** https://sandbox.bonid.ht/api/v1#{'  '}
          - **Local Development:** http://localhost:3000/api/v1
        DESC
      },

      servers: if Rails.env.development?
                 [
                   { url: "http://localhost:3000/api/v1", description: "Local Development (default)" },
                   { url: "https://sandbox.bonid.ht/api/v1", description: "Sandbox" },
                   { url: "https://api.bonid.ht/api/v1", description: "Production" }
                 ]
               else
                 [
                   { url: "https://api.bonid.ht/api/v1", description: "Production" },
                   { url: "https://sandbox.bonid.ht/api/v1", description: "Sandbox" }
                 ]
               end,

      components: {
        securitySchemes: {
          PartnerApiKeyAuth: {
            type: :apiKey,
            name: "X-Partner-Api-Key",
            in: :header,
            description: "Your Partner API key for authenticating BonID requests."
          },
          PartnerHmacAuth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: "HMAC-SHA256",
            description: "Optional advanced authentication with signed HMAC payloads."
          }
        }
      },

      security: [ { PartnerApiKeyAuth: [] } ],

      tags: [
        { name: "Identity", description: "Endpoints for verifying and checking BonIDs" },
        { name: "QR Verification", description: "Ed25519 offline QR code verification" },
        { name: "Partner", description: "Partner usage metrics and key rotation" },
        { name: "Webhook", description: "Partner webhook integrations" }
      ],

      paths: {
        "/verify_identity" => {
          post: {
            tags: [ "Identity" ],
            summary: "Verify identity information against BonID database",
            description: "Performs identity verification and returns verification status.",
            requestBody: {
              required: true,
              content: {
                "application/json" => {
                  schema: {
                    type: :object,
                    properties: {
                      first_name: { type: :string },
                      last_name: { type: :string },
                      dob: { type: :string, format: :date },
                      id_number: { type: :string, description: "CIN or Passport number" }
                    },
                    required: [ "first_name", "last_name" ]
                  }
                }
              }
            },
            responses: {
              "200" => {
                description: "Verification successful",
                content: {
                  "application/json" => {
                    example: {
                      status: "verified",
                      bonid: "MO-1968-M-OU-P6790-H3Z",
                      citizen: {
                        first_name: "Jean",
                        last_name: "Louis",
                        address: "Delmas 33, Port-au-Prince",
                        age: 45
                      },
                      verification: {
                        verified_on: "2025-10-24T14:02:54-04:00",
                        qr_url: "data:image/png;base64,fake_qr_base64"
                      },
                      partner: "Unibank",
                      timestamp: "2025-10-24T12:08:29-04:00"
                    }
                  }
                }
              },
              "404" => { description: "Record not found" },
              "401" => { description: "Unauthorized" }
            }
          }
        },

        "/bonid_status" => {
          get: {
            tags: [ "Identity" ],
            summary: "Retrieve status of a verified BonID",
            description: "Checks if a given BonID is valid and verified.",
            parameters: [
              { name: "bonid", in: :query, required: true, schema: { type: :string } }
            ],
            responses: {
              "200" => {
                description: "BonID found",
                content: {
                  "application/json" => {
                    example: {
                      status: "verified",
                      bonid: "MO-1968-M-OU-P6790-H3Z",
                      citizen: {
                        first_name: "Jean",
                        last_name: "Louis"
                      },
                      verification: {
                        verified_on: "2025-10-23T14:02:54-04:00",
                        qr_url: "data:image/png;base64,fake_qr_base64"
                      },
                      partner: "Unibank",
                      timestamp: "2025-10-24T12:08:29-04:00"
                    }
                  }
                }
              },
              "404" => { description: "BonID not found" },
              "401" => { description: "Unauthorized" }
            }
          }
        },

        "/partner/metrics" => {
          get: {
            tags: [ "Partner" ],
            summary: "Get partner API usage metrics",
            description: "Returns rate limits, request counts, and average latency for your partner API key.",
            responses: {
              "200" => {
                description: "Metrics retrieved successfully",
                content: {
                  "application/json" => {
                    example: {
                      partner: { id: 4, name: "Unibank", sector: "banking" },
                      period: "last_24h",
                      metrics: {
                        total_requests: 45,
                        successful_requests: 44,
                        failed_requests: 1,
                        avg_latency_ms: 85.7
                      },
                      endpoint_breakdown: [
                        { endpoint: "/verify_identity", requests: 30 },
                        { endpoint: "/bonid_status", requests: 15 }
                      ],
                      rate_limit: { limit: 1000, remaining: 955 },
                      generated_at: "2025-10-24T14:51:55-04:00"
                    }
                  }
                }
              },
              "401" => { description: "Unauthorized" },
              "500" => { description: "Internal Server Error" }
            }
          }
        },

        "/public_keys/bonid" => {
          get: {
            tags: [ "QR Verification" ],
            summary: "Get Ed25519 public key for offline QR verification",
            description: "Returns the Ed25519 public key for verifying BonID QR code signatures offline. No authentication required.",
            security: [],
            responses: {
              "200" => {
                description: "Ed25519 public key",
                content: {
                  "application/json" => {
                    example: {
                      algorithm: "Ed25519",
                      public_key: "GBCsejn5DT+48nF9cVGhIeNW952P3CxGM...",
                      encoding: "base64",
                      key_fingerprint: "a1b2c3d4e5f6...",
                      issuer: "bonid.ht",
                      usage: "BonID QR code signature verification",
                      fetched_at: "2026-03-14T04:04:22Z"
                    }
                  }
                }
              },
              "503" => { description: "Ed25519 keys not configured" }
            }
          }
        },

        "/qr_scan" => {
          post: {
            tags: [ "QR Verification" ],
            summary: "Verify a scanned BonID QR code",
            description: "Accepts a QR payload (Base64 or raw JSON) and verifies it. Supports Ed25519 v2 and legacy HMAC v1.",
            requestBody: {
              required: true,
              content: {
                "application/json" => {
                  schema: {
                    type: :object,
                    properties: {
                      qr_data: { type: :string, description: "Base64-encoded or raw JSON QR payload" }
                    },
                    required: [ "qr_data" ]
                  }
                }
              }
            },
            responses: {
              "200" => {
                description: "QR verified — BonID is valid",
                content: {
                  "application/json" => {
                    example: {
                      status: "verified",
                      bonid: "DV-1989-M-SE-P8697-1E8",
                      version: 2
                    }
                  }
                }
              },
              "401" => { description: "Invalid signature or expired QR" },
              "404" => { description: "BonID not found or not verified" },
              "422" => { description: "Malformed QR payload" }
            }
          }
        }
      }
    }
  }

  # === Output Format ===
  config.openapi_format = :yaml
end
