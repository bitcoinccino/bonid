# frozen_string_literal: true

#
# ------------------------------------------------------------------------------
# 🌐 PublicApiController
# Serves public-facing BonID API specification (YAML/JSON)
# and lightweight version metadata for SDKs and external partners.
#
# Motto: Think • Assess • Analyze • Be Productive
# ------------------------------------------------------------------------------

class PublicApiController < ActionController::Base
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :authenticate_partner!, raise: false
  skip_before_action :authenticate_admin!, raise: false

  SPEC_PATH = Rails.root.join("public", "api", "v1", "bonid_open_identity.yaml")

  # --------------------------------------------------------------------------
  # GET /api/v1/openapi.yaml
  # --------------------------------------------------------------------------
  def openapi
    if File.exist?(SPEC_PATH)
      send_file SPEC_PATH, type: "application/yaml", disposition: "inline"
    else
      render plain: "Spec not found", status: :not_found
    end
  end

  # --------------------------------------------------------------------------
  # GET /api/v1/openapi.json
  # --------------------------------------------------------------------------
  def openapi_json
    if File.exist?(SPEC_PATH)
      yaml_content = YAML.safe_load(File.read(SPEC_PATH))
      render json: yaml_content
    else
      render json: { error: "Spec not found" }, status: :not_found
    end
  end

  # --------------------------------------------------------------------------
  # GET /api/version
  # --------------------------------------------------------------------------
  def version
    spec_version = extract_version_from_yaml

    render json: {
      api: "BonID Open Identity API",
      version: spec_version || "unknown",
      environment: Rails.env,
      updated_at: File.exist?(SPEC_PATH) ? File.mtime(SPEC_PATH).iso8601 : nil,
      docs_url: "#{request.base_url}/api-docs",
      json_spec_url: "#{request.base_url}/api/v1/openapi.json",
      yaml_spec_url: "#{request.base_url}/api/v1/openapi.yaml"
    }
  end

  private

  def extract_version_from_yaml
    return unless File.exist?(SPEC_PATH)
    yaml = YAML.safe_load(File.read(SPEC_PATH))
    yaml.dig("info", "version")
  rescue StandardError
    nil
  end
end
