# frozen_string_literal: true

# ------------------------------------------------------------------------------
# 🧭 BonID API Version Headers
# Injects versioning and environment metadata into every API::V1 response.
# This helps clients, SDKs, and partner systems identify which API build
# they are communicating with.
# ------------------------------------------------------------------------------

module ApiResponseHeaders
  extend ActiveSupport::Concern

  included do
    after_action :set_bonid_api_headers
  end

  private

  def set_bonid_api_headers
    response.set_header("X-BonID-API-Version", "1.4.0") # 🔄 keep in sync with OpenAPI spec
    response.set_header("X-BonID-Environment", Rails.env)
    response.set_header("X-BonID-Timestamp", Time.current.utc.iso8601)
  end
end

# ✅ Automatically include headers into all API controllers
Rails.application.config.to_prepare do
  if defined?(Api::V1::BaseController)
    Api::V1::BaseController.include(ApiResponseHeaders)
  end
end
