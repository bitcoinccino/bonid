# frozen_string_literal: true

# ------------------------------------------------------------------------------
# 🧩 Namespace Loader for BonID API
# Ensures Zeitwerk autoloads Api and Api::V1 namespaces cleanly.
# This helps when controllers/models live under app/controllers/api/v1/
# ------------------------------------------------------------------------------

module Api
  module V1
  end
end
