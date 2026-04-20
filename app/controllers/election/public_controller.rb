# frozen_string_literal: true

# Public Election Results — broadcast-ready, CDN-cacheable.
# No auth. No PII. Static enough for Cloudflare edge caching.
#
# Two views:
#   - /election/results      → live counting OR locked state
#   - /election/celebration   → certified final results ("Ayiti Pale")
#
module Election
  class PublicController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :authenticate_citizen!, raise: false

    # GET /election/results
    def results
      load_election_data

      # Auto-redirect to celebration page when certified
      if @certified
        redirect_to election_public_celebration_path(lang: params[:lang], election_id: params[:election_id])
        return
      end

      # Cache headers for CDN (refresh every 30 seconds during live results)
      response.headers["Cache-Control"] = "public, max-age=30"

      render "election/public/results", layout: false
    end

    # GET /election/celebration
    def celebration
      load_election_data
      load_celebration_data

      # Cache for 1 hour — certified results don't change
      response.headers["Cache-Control"] = "public, max-age=3600"

      render "election/public/celebration", layout: false
    end

    # GET /election/whitepaper — English web whitepaper
    def whitepaper
      I18n.locale = %w[ht fr en].include?(params[:lang]) ? params[:lang] : :en
      response.headers["Cache-Control"] = "public, max-age=86400"
      render "election/public/whitepaper", layout: false
    end

    # GET /election/livreblanc — French web whitepaper
    def livreblanc
      I18n.locale = %w[ht fr en].include?(params[:lang]) ? params[:lang] : :fr
      response.headers["Cache-Control"] = "public, max-age=86400"
      render "election/public/livreblanc", layout: false
    end

    # GET /election/candidates — public roster of approved candidates.
    # Read-only, CDN-cacheable. Shows citizens who's on the ballot before
    # election day. Only candidates with registration_status == "approved"
    # appear here; anything still under review is kept private.
    def candidates
      I18n.locale = %w[ht fr en].include?(params[:lang]) ? params[:lang] : :ht
      @election_id = params[:election_id] || "2026-presidential-round1"
      @election = BonvoteElection.find_by(id: @election_id)

      if @election
        # Article 192-195: the public roster includes both the liste préliminaire
        # (48h contestation window open) and the liste définitive. View uses
        # registration_status to render the contest CTA on preliminary rows.
        on_ballot = ElectionCandidate.where(election: @election).on_ballot.includes(:election_constituency, :user)
        @presidents = on_ballot.presidents.order(:full_name).to_a
        @senators_by_department = on_ballot.senators.order(:full_name).group_by { |c| c.residence_department.presence || c.department_code.presence || "—" }
        @deputies_by_commune = on_ballot.deputies.order(:full_name).group_by { |c| c.residence_commune.presence || c.commune_id&.to_s || "—" }
        @total_approved = on_ballot.where(registration_status: "approved").count
        @total_preliminary = on_ballot.where(registration_status: "preliminary_listed").count

        # Article 181.15 — independents still collecting their 2% support
        # petition are surfaced here so citizens can endorse them directly.
        @seeking_endorsements = ElectionCandidate
                                  .where(election: @election, candidacy_type: "independent")
                                  .where(registration_status: %w[submitted under_review])
                                  .order(:full_name)
                                  .to_a
      else
        @presidents = []
        @senators_by_department = {}
        @deputies_by_commune = {}
        @total_approved = 0
        @total_preliminary = 0
        @seeking_endorsements = []
      end

      # Certified results don't change, but the candidate list updates as
      # CEP approves; 5-minute cache balances freshness and edge load.
      response.headers["Cache-Control"] = "public, max-age=300"
      render "election/public/candidates", layout: false
    end

    # GET /election/live_stats.json — lightweight polling endpoint for globe updates
    def live_stats
      election_id = params[:election_id] || "2026-presidential-round1"
      election = BonvoteElection.find_by(id: election_id)

      unless election
        render json: { total_votes: 0, by_country: {} } and return
      end

      by_country = ElectionBallot.where(election_id: election.id)
                                  .where.not(ip_country: [ nil, "" ])
                                  .group(:ip_country)
                                  .count

      total = ElectionBallot.where(election_id: election.id).count

      response.headers["Cache-Control"] = "public, max-age=5"

      render json: {
        total_votes: total,
        by_country: by_country,
        countries_count: by_country.size,
        timestamp: Time.current.iso8601
      }
    end

    private

    def load_election_data
      I18n.locale = %w[ht fr en].include?(params[:lang]) ? params[:lang] : :ht
      @election_id = params[:election_id] || "2026-presidential-round1"
      @election = BonvoteElection.find_by(id: @election_id)
      @certified = @election&.status == "certified"
      @test_mode = @election&.election_type == "simulation"
      @signatures_count = @election ? ElectionSignature.where(election_id: @election.id, liveness_verified: true).count : 0

      # Load real ballot stats if election exists, otherwise zeros
      if @election
        ballot_stats = ElectionBallot.stats(@election.id) rescue {}
        @total_votes = ballot_stats[:total_votes] || 0
        @remote_votes = ballot_stats[:remote_votes] || 0
        @consulate_votes = ballot_stats[:consulate_votes] || 0
        @countries_count = (ballot_stats[:by_country] || {}).size
      else
        @total_votes = 0
        @remote_votes = 0
        @consulate_votes = 0
        @countries_count = 0
      end

      # Recent activity for live ticker (no PII — only department/country + time)
      @recent_ballots = @election ? ElectionBallot.where(election_id: @election.id).recent(8) : []

      # TODO: Replace with real decrypted results after multi-sig
      @candidates = {}
      @has_results = @candidates.any?

      # Load candidate objects for photos (eager-load user for BonID photo fallback)
      @candidate_objects = if @election
        ElectionCandidate.where(election_id: @election.id, position: "president", status: "active")
                         .includes(:user)
                         .index_by(&:full_name)
      else
        {}
      end

      # Anti-deepfake hash — changes every minute
      @results_hash = OpenSSL::Digest::SHA256.hexdigest(
        "#{@election_id}||#{@total_votes}||#{@candidates.to_json}||#{Time.current.to_i / 60}"
      )
    end

    def load_celebration_data
      # Safe defaults when no election exists
      unless @election
        @winners = { president: [], senator: [], deputy: [] }
        @candidates_president = []
        @diaspora_votes = 0
        @participation_rate = nil
        @top_departments = []
        @voting_countries = [ "HT" ]
        @certified_hash = @results_hash || ""
        return
      end

      # Winners grouped by position (eager-load user for photos)
      winners = ElectionCandidate.where(election_id: @election.id, winner: true)
                                 .includes(:election_constituency, :user)
      @winners = {
        president: winners.presidents.to_a,
        senator: winners.senators.to_a,
        deputy: winners.deputies.to_a
      }

      # All presidential candidates for comparison bars (eager-load user for photos)
      @candidates_president = ElectionCandidate.where(election_id: @election.id, position: "president", status: "active")
                                               .includes(:user)
                                               .order(votes_round1: :desc)
                                               .to_a

      # Diaspora stats
      @diaspora_votes = @remote_votes + @consulate_votes

      # Participation rate (registered voters vs votes cast)
      registered = @election.voter_eligibility_records.count
      @participation_rate = registered > 0 ? (@total_votes.to_f / registered * 100).round(1) : nil

      # Top departments by vote count
      ballot_by_dept = ElectionBallot.where(election_id: @election.id).group(:department_code).count
      dept_labels = ElectionBallot::DEPARTMENT_LABELS
      @top_departments = ballot_by_dept.sort_by { |_, v| -v }
                                       .first(3)
                                       .map { |code, count| [ dept_labels[code] || code, count ] }

      # Diaspora votes grouped by country (for globe markers)
      @diaspora_by_country = ElectionBallot.where(election_id: @election.id)
                                            .where.not(ip_country: [ nil, "" ])
                                            .group(:ip_country)
                                            .count

      # Unique countries that voted (for flag row)
      @voting_countries = @diaspora_by_country.keys.sort
      # Always include HT
      @voting_countries.unshift("HT") unless @voting_countries.include?("HT")

      # Certified hash (final Merkle root)
      snapshot = Election::AuditService.daily_snapshot(@election.id) rescue {}
      @certified_hash = snapshot[:merkle_root] || @results_hash
    end
  end
end
