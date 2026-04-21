# frozen_string_literal: true

# Oath-before-registration surface for the clerk-assisted path.
# VoterOathAcknowledgement model exists (app/models/voter_oath_acknowledgement.rb)
# and is currently wired to the citizen vote controller; this stub is where
# the ajan-assisted oath capture will land when the enrollment flow is wired.
module Ajan
  module Cep
    class OathsController < Ajan::ApplicationController
      def new
      end
    end
  end
end
