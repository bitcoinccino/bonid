# frozen_string_literal: true

# CEP Ajan voter-enrollment stub. Full flow (Scan BonID → verify identity
# → oath → register voter) will be wired in the next pass; this view
# just gives the sidebar link something to render so the chrome doesn't
# 404 during v1 rollout.
module Ajan
  module Cep
    class VoterEnrollmentsController < Ajan::ApplicationController
      def new
      end
    end
  end
end
