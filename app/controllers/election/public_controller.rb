# frozen_string_literal: true

# Public Election Results — broadcast-ready, CDN-cacheable.
# No auth. No PII. Static enough for Cloudflare edge caching.
#
module Election
  class PublicController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :authenticate_citizen!, raise: false

    # GET /election/results
    def results
      I18n.locale = %w[ht fr en].include?(params[:lang]) ? params[:lang] : :ht
      @election_id = params[:election_id] || "2026-presidential-round1"
      @certified = false # Set true after multi-sig ceremony

      # TODO: Replace with real ElectionBallot queries
      @total_votes = 0
      @remote_votes = 0
      @consulate_votes = 0
      @countries_count = 0

      # TODO: Replace with real decrypted results after multi-sig
      @candidates = {}
      # Example when results are live:
      # @candidates = {
      #   "Jean-Baptiste Aristide" => 185000,
      #   "Maryse Narcisse" => 142000,
      #   "Jovenel Moïse" => 98000,
      #   "Moise Jean-Charles" => 75000
      # }

      # Anti-deepfake hash — changes every minute
      @results_hash = OpenSSL::Digest::SHA256.hexdigest(
        "#{@election_id}||#{@total_votes}||#{@candidates.to_json}||#{Time.current.to_i / 60}"
      )

      # Cache headers for CDN (refresh every 30 seconds during live results)
      if @certified
        response.headers["Cache-Control"] = "public, max-age=3600" # 1 hour after certified
      else
        response.headers["Cache-Control"] = "public, max-age=30" # 30s during live counting
      end

      render "election/public/results", layout: false
    end
  end
end
