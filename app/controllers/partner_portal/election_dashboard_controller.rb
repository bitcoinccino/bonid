# frozen_string_literal: true

module PartnerPortal
  class ElectionDashboardController < BaseController
    before_action :enforce_bonvote_tally_flag!
    before_action :set_election

    # GET /partner_portal/election/:id/tablo
    def show
      @stats = build_stats(@election_id)
      @sig_status = ElectionSignature.status_for(@election_id)

      @integrity = Election::AuditService.generate_tally_proof(@election_id)
      integrity_check = Election::AuditService.verify_ledger_integrity(
        @election_id,
        @integrity[:merkle_root] || ""
      )
      @integrity[:valid] = integrity_check[:valid]
      @integrity[:verified_at] = integrity_check[:verified_at]

      render "election/admin/tally"
    end

    # GET /partner_portal/election/:id/multi_sig
    def multi_sig
      @sig_status = Election::MultiSigService.status(@election_id)

      render "election/admin/multi_sig"
    end

    # GET /partner_portal/election/:id/results
    def results
      @sig_status = ElectionSignature.status_for(@election_id)
      @stats = build_stats(@election_id)
      @integrity = Election::AuditService.generate_tally_proof(@election_id)
      @results = build_results(@election_id)

      render "election/admin/results"
    end

    private

    # Ballot-tally stack is shelved behind FEATURE_BONVOTE_TALLY.
    # See project_bonid_cep_sovereignty_line memory (2026-04-20).
    def enforce_bonvote_tally_flag!
      return if Features.bonvote_tally?

      redirect_to partner_portal_dashboard_path,
                  alert: "Fonksyonalite sa a poze — BonID ap fè verifikasyon sèlman pou CEP kounye a."
    end

    def set_election
      @election_id = params[:id]
      @election = BonvoteElection.find_by(id: @election_id)
      @election_closed = @election&.closed? || @election&.certified? || false
    end

    def build_stats(election_id)
      stats = ElectionBallot.stats(election_id)

      consulate_votes = ElectionBallot.where(election_id: election_id, channel: "consulate")
                                      .group(:consulate_id).count

      consulates = HaitianDiplomaticMissions::ALL_MISSIONS.map do |mission|
        mission.merge(
          votes: consulate_votes[mission[:id]] || 0,
          status: consulate_votes[mission[:id]].to_i > 0 ? "active" : "standby"
        )
      end

      by_country = ElectionBallot.where(election_id: election_id)
                                 .where.not(ip_country: nil)
                                 .group(:ip_country).count

      stats.merge(
        rejected: ElectionBallot.where(election_id: election_id).flagged.count,
        in_person_votes: ElectionBallot.where(election_id: election_id).in_person.count,
        by_country: by_country,
        consulates: consulates
      )
    end

    def build_results(election_id)
      candidates = ElectionCandidate.where(election_id: election_id, position: "president", status: "active")
                                    .order(votes_round1: :desc)

      election = BonvoteElection.find_by(id: election_id)
      round = election&.round || 1
      vote_field = round == 2 ? :votes_round2 : :votes_round1

      candidate_results = candidates.each_with_object({}) do |c, hash|
        hash[c.display_name] = c.send(vote_field)
      end

      {
        election_id: election_id,
        decrypted_at: election&.certified_at&.iso8601 || Time.current.iso8601,
        candidates: candidate_results
      }
    end
  end
end
