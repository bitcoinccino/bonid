# frozen_string_literal: true

# Shared Scan BonID primitive for the Agent Portal. Every sector's agent
# uses this as the starting action — the scan result then routes to the
# sector-specific next step (CEP → enroll voter, banking → open account, etc.).
module Ajan
  class ScansController < Ajan::ApplicationController
    # QR camera scan page. Mirrors PartnerPortal::ScansController#index — the
    # page itself just renders the scanner UI; the actual BonID lookup POSTs
    # to ajan_bonid_lookups_path via the partner-scanner Stimulus controller.
    def index
    end
  end
end
