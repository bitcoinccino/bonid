# frozen_string_literal: true

# Public documentation page describing how to reconstruct the canonical
# signing payload for a BonVote receipt and verify it offline.
#
# Stable contract — third parties (CEP tablets, election observers,
# journalists, watchdog NGOs) link to this URL from their tooling so they
# can build interoperable verifiers without reading our source.
#
# Versioned in the URL (`/spec/receipt-v1`) so a payload format bump
# becomes `/spec/receipt-v2` while v1 stays canonically described forever.
module Election
  class ReceiptSpecController < ApplicationController
    skip_before_action :authenticate_user!,    raise: false
    skip_before_action :authenticate_citizen!, raise: false

    def show
      render layout: false
    end
  end
end
