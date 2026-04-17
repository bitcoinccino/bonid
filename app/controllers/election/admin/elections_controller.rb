# frozen_string_literal: true

# CEP Admin Elections Controller — the "Command Center"
#
# Access: CEP administrators only (role-gated).
# Shows real-time participation, integrity monitoring,
# and the final decryption trigger.
#
module Election
  module Admin
    class ElectionsController < ::Admin::BaseController
      before_action :require_cep_admin!
      before_action :set_election, except: [ :snapshot ]

      # GET /election/:id
      # The main tally dashboard
      def show
        @stats = build_stats(@election_id)
        @sig_status = ElectionSignature.status_for(@election_id)

        # Integrity verification
        @integrity = Election::AuditService.generate_tally_proof(@election_id)
        integrity_check = Election::AuditService.verify_ledger_integrity(
          @election_id,
          @integrity[:merkle_root] || ""
        )
        @integrity[:valid] = integrity_check[:valid]
        @integrity[:verified_at] = integrity_check[:verified_at]

        render "election/admin/tally"
      end

      # GET /election/:id/snapshot
      # Daily snapshot for public publication
      def snapshot
        @election_id = params[:id]
        snapshot = Election::AuditService.daily_snapshot(@election_id)

        respond_to do |format|
          format.json { render json: snapshot }
          format.csv do
            csv = generate_snapshot_csv(snapshot)
            send_data csv, filename: "bonid-election-snapshot-#{Date.current.iso8601}.csv"
          end
        end
      end

      # GET /election/:id/multi_sig
      # Multi-signature ceremony UI
      def multi_sig
        @sig_status = Election::MultiSigService.status(@election_id)

        render "election/admin/multi_sig"
      end

      # POST /election/:id/sign
      # Add a signatory's signature
      def sign
        signatory = {
          bonid: current_admin_user.try(:bonid) || params[:bonid],
          role: params[:role],
          name: current_admin_user.try(:full_name) || params[:name] || current_admin_user.try(:email),
          liveness_session_id: params[:liveness_session_id],
          liveness_verified: params[:liveness_verified].present? || params[:liveness_session_id].present?,
          key_shard: params[:key_shard]
        }

        result = Election::MultiSigService.add_signature(@election_id, signatory)

        if result[:quorum_met]
          redirect_to admin_election_election_results_path(@election_id),
                      notice: "Kowòm atenn! Rezilta yo disponib."
        else
          redirect_to admin_election_election_multi_sig_path(@election_id),
                      notice: "Siyati anrejistre. #{result[:remaining]} rete."
        end
      rescue Election::MultiSigService::DuplicateSignatureError => e
        redirect_to admin_election_election_multi_sig_path(@election_id), alert: e.message
      rescue Election::MultiSigService::InvalidSignatoryError => e
        redirect_to admin_election_election_multi_sig_path(@election_id), alert: e.message
      end

      # GET /election/:id/results
      # Official results (only after multi-sig quorum)
      def results
        @sig_status = ElectionSignature.status_for(@election_id)
        @stats = build_stats(@election_id)
        @integrity = Election::AuditService.generate_tally_proof(@election_id)
        @results = build_results(@election_id)

        render "election/admin/results"
      end

      # POST /election/:id/decrypt
      # The "Grand Decryption" — requires multi-sig authorization
      def decrypt
        @sig_status = ElectionSignature.status_for(@election_id)

        unless @sig_status[:met]
          redirect_to admin_election_election_multi_sig_path(@election_id),
                      alert: "Kowòm pa atenn. #{@sig_status[:remaining]} siyati rete."
          return
        end

        @stats = build_stats(@election_id)
        @integrity = Election::AuditService.generate_tally_proof(@election_id)
        @results = build_results(@election_id)

        render "election/admin/results"
      rescue => e
        Rails.logger.error("[Election::Decrypt] Failed: #{e.message}")
        redirect_to admin_election_election_path(@election_id),
                    alert: "Erè nan dechifraj: #{e.message}"
      end

      private

      def set_election
        @election_id = params[:id]
        @election = BonvoteElection.find_by(id: @election_id)
        @election_closed = @election&.closed? || @election&.certified? || false
      end

      def require_cep_admin!
        unless current_admin_user.present?
          redirect_to admin_login_path, alert: "Aksè refize. Sèlman administratè CEP ka wè paj sa a."
        end
      end

      def build_stats(election_id)
        stats = ElectionBallot.stats(election_id)

        # Consulate station details with live vote counts
        consulate_votes = ElectionBallot.where(election_id: election_id, channel: "consulate")
                                        .group(:consulate_id).count

        consulates = HaitianDiplomaticMissions::ALL_MISSIONS.map do |mission|
          mission.merge(
            votes: consulate_votes[mission[:id]] || 0,
            status: consulate_votes[mission[:id]].to_i > 0 ? "active" : "standby"
          )
        end

        # Votes by country (from ip_country)
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

      def generate_snapshot_csv(snapshot)
        CSV.generate do |csv|
          csv << [ "Election ID", "Date", "Total Votes", "Merkle Root", "Published At" ]
          csv << [
            snapshot[:election_id],
            snapshot[:snapshot_date],
            snapshot[:total_votes],
            snapshot[:merkle_root],
            snapshot[:published_at]
          ]
          csv << []
          csv << [ "Channel", "Vote Count" ]
          (snapshot[:votes_by_channel] || {}).each { |k, v| csv << [ k, v ] }
          csv << []
          csv << [ "Hour", "Vote Count" ]
          (snapshot[:votes_by_hour] || {}).each { |k, v| csv << [ k, v ] }
        end
      end
    end
  end
end
