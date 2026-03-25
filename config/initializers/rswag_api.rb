# frozen_string_literal: true

# ------------------------------------------------------------------------------
# Rswag::Api Configuration
#
# Serves the BonID OpenAPI spec from:
#   public/api/v1/bonid_open_identity.yaml
#
# Endpoints:
#   /api/swagger  → Rswag JSON spec endpoint
#   /api-docs     → Swagger UI frontend (Rswag::Ui)
# ------------------------------------------------------------------------------

Rswag::Api.configure do |c|
  c.openapi_root = Rails.root.join("public", "api", "v1").to_s

  c.swagger_filter = lambda do |swagger, env|
    spec_file = Rails.root.join("public", "api", "v1", "bonid_open_identity.yaml")
    next unless File.exist?(spec_file)

    yaml_spec = YAML.safe_load(File.read(spec_file))
    swagger.deep_merge!(yaml_spec)
  end
end
