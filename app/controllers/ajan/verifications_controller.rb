# frozen_string_literal: true

# Shared "verify identity" surface — sector-agnostic lookup of a scanned
# BonID that returns the verified person card. Same primitive as the
# reviewer's identity_submissions flow, but read-only from the agent's
# perspective (agents don't approve submissions, they consume verified ones).
module Ajan
  class VerificationsController < Ajan::ApplicationController
    def new
    end
  end
end
