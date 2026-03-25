# frozen_string_literal: true

# ------------------------------------------------------------------------------
# Rswag::Ui Configuration
# Configures Swagger UI at /swagger (and /api-docs via redirect)
# to serve the BonID OpenAPI spec.
# ------------------------------------------------------------------------------

Rswag::Ui.configure do |c|
  c.openapi_endpoint "/api/swagger/bonid_open_identity.yaml", "BonID Open Identity & Partner API v1.4"
  c.config_object["deepLinking"] = true
  c.config_object["defaultModelsExpandDepth"] = 2
  c.config_object["displayRequestDuration"] = true
  c.config_object["filter"] = true
  c.config_object["tryItOutEnabled"] = true
end
