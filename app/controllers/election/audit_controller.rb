# frozen_string_literal: true

# Public Audit Controller — no login required.
#
# Allows any person (voter, observer, journalist) to:
#   - Verify a ballot hash exists in the public ledger
#   - View daily snapshots
#   - Download the full ledger for independent audit
#
module Election
  class AuditController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :authenticate_citizen!, raise: false

    # GET /election/audit/verify?h=BALLOT_HASH&lang=en|fr|ht
    # Locale is set by ApplicationController#set_locale (before_action)
    def verify
      ballot_hash = params[:h].to_s.strip
      election_id = params[:election_id] || "2026-presidential-round1"

      if ballot_hash.present?
        @result = Election::AuditService.verify_ballot_presence(ballot_hash, election_id)
      else
        @result = { found: false, message: "Antre nimewo resi ou pou verifye." }
      end

      # Live stats for the heartbeat
      snapshot = Election::AuditService.daily_snapshot(election_id)
      @total_votes = snapshot[:total_votes] || 0
      @countries_count = (snapshot[:votes_by_channel] || {}).size
      @departments_count = 10 # All 10 Haitian departments
      @merkle_root = snapshot[:merkle_root]

      I18n.locale = %w[ht fr en].include?(params[:lang]) ? params[:lang] : :ht
      render "election/audit/verify", layout: false
    end

    # GET /election/audit/snapshot.json
    def snapshot
      election_id = params[:election_id] || "2026-presidential-round1"
      snapshot = Election::AuditService.daily_snapshot(election_id)

      render json: snapshot
    end
  end
end
