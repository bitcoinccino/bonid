# frozen_string_literal: true

# MonCash Payment Gateway Configuration
# https://sandbox.moncashbutton.digicelgroup.com
#
# Set the following environment variables:
#   MONCASH_CLIENT_ID       - Your MonCash business client ID
#   MONCASH_CLIENT_SECRET   - Your MonCash business client secret
#   MONCASH_ENV             - "sandbox" or "production" (defaults to sandbox)

MONCASH_CONFIG = {
  client_id: ENV.fetch("MONCASH_CLIENT_ID", nil),
  client_secret: ENV.fetch("MONCASH_CLIENT_SECRET", nil),
  environment: ENV.fetch("MONCASH_ENV", "sandbox"),
  api_base: if ENV.fetch("MONCASH_ENV", "sandbox") == "production"
              "https://moncashbutton.digicelgroup.com/Api"
            else
              "https://sandbox.moncashbutton.digicelgroup.com/Api"
            end,
  gateway_base: if ENV.fetch("MONCASH_ENV", "sandbox") == "production"
                  "https://moncashbutton.digicelgroup.com"
                else
                  "https://sandbox.moncashbutton.digicelgroup.com"
                end
}.freeze
