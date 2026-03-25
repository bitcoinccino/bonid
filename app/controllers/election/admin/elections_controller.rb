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

      # GET /election/admin/elections/:id
      # The main tally dashboard
      def show
        @election_id = params[:id] || "2026-presidential-round1"
        @election_closed = false # TODO: Check election.closed_at

        # Vote counts
        @stats = build_stats(@election_id)

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

      # GET /election/admin/elections/:id/snapshot
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

      # POST /election/admin/elections/:id/decrypt
      # The "Grand Decryption" — requires multi-sig authorization
      def decrypt
        @election_id = params[:id] || params[:election_id]
        cep_private_key = params[:cep_private_key]

        # TODO: Implement multi-sig (3 of 5 CEP board members)
        # For now, single key decryption
        if cep_private_key.blank?
          redirect_to election_admin_election_path(@election_id),
                      alert: "Kle prive CEP a obligatwa pou dechifre rezilta yo."
          return
        end

        begin
          # Decrypt aggregated results
          # In production, this decrypts the homomorphic sum of all commitments
          @results = decrypt_final_tally(@election_id, cep_private_key)

          render "election/admin/results"
        rescue OpenSSL::PKey::RSAError => e
          redirect_to election_admin_election_path(@election_id),
                      alert: "Kle prive a pa valid: #{e.message}"
        rescue => e
          Rails.logger.error("[Election::Decrypt] Failed: #{e.message}")
          redirect_to election_admin_election_path(@election_id),
                      alert: "Erè nan dechifraj: #{e.message}"
        end
      end

      private

      def require_cep_admin!
        # TODO: Check for CEP-specific role
        # For now, any admin user can access
        unless current_admin_user.present?
          redirect_to admin_login_path, alert: "Aksè refize. Sèlman administratè CEP ka wè paj sa a."
        end
      end

      def build_stats(election_id)
        # TODO: Replace with real ElectionBallot queries once model exists
        ballots = [] # ElectionBallot.where(election_id: election_id)

        total = ballots.size
        remote = ballots.count { |b| b[:channel] != "consulate" }
        consulate = total - remote

        # Group by country
        by_country = ballots.group_by { |b| b[:country] || "HT" }
                            .transform_values(&:size)

        # Consulate stations
        consulates = [
          { id: "HT-CONS-MIAMI", name: "Miami, FL", country: "US", votes: 0, status: "active" },
          { id: "HT-CONS-NYC", name: "New York, NY", country: "US", votes: 0, status: "active" },
          { id: "HT-CONS-BOS", name: "Boston, MA", country: "US", votes: 0, status: "active" },
          { id: "HT-CONS-CHI", name: "Chicago, IL", country: "US", votes: 0, status: "standby" },
          { id: "HT-CONS-MTL", name: "Montréal, QC", country: "CA", votes: 0, status: "active" },
          { id: "HT-CONS-PAR", name: "Paris", country: "FR", votes: 0, status: "active" },
          { id: "HT-CONS-SDQ", name: "Santo Domingo", country: "DO", votes: 0, status: "active" },
          { id: "HT-CONS-SCL", name: "Santiago", country: "CL", votes: 0, status: "active" },
          { id: "HT-CONS-BSB", name: "Brasília", country: "BR", votes: 0, status: "standby" },
          { id: "HT-CONS-NAS", name: "Nassau", country: "BS", votes: 0, status: "standby" }
        ]

        {
          total_votes: total,
          remote_votes: remote,
          consulate_votes: consulate,
          rejected: 0,
          by_country: by_country,
          consulates: consulates
        }
      end

      def decrypt_final_tally(election_id, cep_private_key)
        # TODO: Implement homomorphic decryption of aggregated commitments
        # This is the final step — CEP decrypts ONLY the total, never individual votes
        {
          election_id: election_id,
          decrypted_at: Time.current.iso8601,
          results: {} # { candidate_1: count, candidate_2: count, ... }
        }
      end

      def generate_snapshot_csv(snapshot)
        CSV.generate do |csv|
          csv << ["Election ID", "Date", "Total Votes", "Merkle Root", "Published At"]
          csv << [
            snapshot[:election_id],
            snapshot[:snapshot_date],
            snapshot[:total_votes],
            snapshot[:merkle_root],
            snapshot[:published_at]
          ]
          csv << []
          csv << ["Channel", "Vote Count"]
          (snapshot[:votes_by_channel] || {}).each { |k, v| csv << [k, v] }
          csv << []
          csv << ["Hour", "Vote Count"]
          (snapshot[:votes_by_hour] || {}).each { |k, v| csv << [k, v] }
        end
      end
    end
  end
end
