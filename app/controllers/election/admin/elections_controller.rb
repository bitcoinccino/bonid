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
      include Election::Admin::CepAdminGate
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

      # GET /election/:id/oaths
      # Signed-oath audit trail for the election — one row per voter
      # (per oath_version). CEP uses this for dispute investigations and
      # the evidentiary chain that precedes every ballot.
      def oaths
        scope = VoterOathAcknowledgement
                  .includes(:user, :identity_submission)
                  .for_election(@election)
                  .recent_first

        if params[:q].present?
          q = params[:q].to_s.strip
          scope = scope.joins(:user).where(
            "users.bonid ILIKE :q OR users.first_name ILIKE :q OR users.last_name ILIKE :q",
            q: "%#{q}%"
          )
        end

        @oath_total = VoterOathAcknowledgement.for_election(@election).count
        @oath_latest = VoterOathAcknowledgement.for_election(@election).maximum(:accepted_at)
        @oath_records = scope.page(params[:page]).per(50)

        render "election/admin/oaths"
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

      # GET /admin/election/:id/edit
      # Edit policy flags (online voting / digital enrollment) + title/date
      # before an election opens. CEP-only; see CepAdminGate.
      def edit
        return redirect_missing unless @election

        render "election/admin/edit"
      end

      # PATCH /admin/election/:id
      def update
        return redirect_missing unless @election

        if @election.update(election_update_params)
          Election::ElectionCache.bust(@election.id) if defined?(Election::ElectionCache)
          redirect_to admin_election_election_path(@election.id),
                      notice: "Règ eleksyon yo mete ajou."
        else
          flash.now[:alert] = @election.errors.full_messages.to_sentence
          render "election/admin/edit", status: :unprocessable_entity
        end
      end

      # POST /admin/election/:id/certify
      # Stamps durable winners into the `election_winners` table, then
      # flips status → certified. Requires the quorum + decrypt to have
      # already happened (results must be visible before certification).
      def certify
        return redirect_missing unless @election

        unless @election.closed?
          redirect_to admin_election_election_results_path(@election.id),
                      alert: "Yon eleksyon dwe fèmen anvan sètifikasyon."
          return
        end

        sig_status = ElectionSignature.status_for(@election_id)
        unless sig_status[:met]
          redirect_to admin_election_election_multi_sig_path(@election.id),
                      alert: "Kowòm siyati pa atenn. #{sig_status[:remaining]} rete."
          return
        end

        result = Election::WinnerStampingService.call(@election, stamped_by: current_admin_user)
        redirect_to admin_election_election_results_path(@election.id),
                    notice: "Eleksyon sètifye — #{result[:winners_count]} genyan anrejistre."
      rescue Election::WinnerStampingService::Error => e
        redirect_to admin_election_election_results_path(@election.id),
                    alert: "Sètifikasyon echwe: #{e.message}"
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

      # The handful of fields CEP admins can change via the web UI. Status
      # transitions (open/close/certify) happen through dedicated actions,
      # never free-form updates. Round + election_type are locked once the
      # election exists to prevent accidental reshaping of a live ballot.
      def election_update_params
        params.require(:bonvote_election).permit(
          :title,
          :election_date,
          :allows_online_voting,
          :allows_digital_enrollment
        )
      end

      def redirect_missing
        redirect_to admin_root_path, alert: "Eleksyon pa jwenn."
      end

      def set_election
        @election_id = params[:id]
        @election = BonvoteElection.find_by(id: @election_id)
        @election_closed = @election&.closed? || @election&.certified? || false
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
        election = BonvoteElection.find_by(id: election_id)
        round = election&.round || 1
        vote_field = round == 2 ? :votes_round2 : :votes_round1

        # Once certified, serve from the durable winners table so the
        # numbers can't drift if a candidate row is edited later.
        if election&.certified? && ElectionWinner.for_election(election).exists?
          winners = ElectionWinner.for_election(election).includes(:election_candidate).ordered
          candidate_results = winners.each_with_object({}) do |w, hash|
            hash[w.election_candidate.display_name] = w.vote_count
          end

          return {
            election_id:  election_id,
            decrypted_at: election.certified_at.iso8601,
            candidates:   candidate_results,
            source:       "certified_winners"
          }
        end

        # Pre-certification: compute on-the-fly for live preview.
        candidates = ElectionCandidate.where(election_id: election_id, position: "president", status: "active")
                                      .order(vote_field => :desc)

        candidate_results = candidates.each_with_object({}) do |c, hash|
          hash[c.display_name] = c.send(vote_field)
        end

        {
          election_id:  election_id,
          decrypted_at: election&.certified_at&.iso8601 || Time.current.iso8601,
          candidates:   candidate_results,
          source:       "live"
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
