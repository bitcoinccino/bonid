# frozen_string_literal: true

# Election::WinnerStampingService — at certification, walks every
# constituency in the election, applies the electoral rule for that seat,
# and writes one `ElectionWinner` row per seat filled.
#
# Why not compute-on-the-fly in the view?
#
#   - The Rezilta view otherwise re-runs vote aggregations on every load.
#     Winners are frozen facts; storing them once eliminates that work.
#   - Downstream pipelines (press-release PDF, JSON export for media,
#     Gazette publishing) need a single source of truth independent of the
#     ballot table — which might be pruned post-archival.
#   - Preserves a historical record even if `election_candidates.winner`
#     flags drift (bug, migration, admin mistake).
#
# The service also updates the legacy `ElectionCandidate.winner` boolean
# for backward compatibility with existing scopes (`.winners`,
# `.runoff_qualified`) until callers migrate to the new table.
#
# Electoral rules per position (v1 scope — matches BonvoteElection#create_runoff!):
#
#   - president:  top vote-getter. Runoff is created separately via
#                 BonvoteElection#create_runoff! when no majority in round 1;
#                 at that point president is *not* stamped (there's no winner
#                 yet — the runoff election will stamp it on its own certify).
#   - senator:    top-N by `constituency.seats` (plurality / block vote).
#   - deputy:     top vote-getter for the commune.
#   - Dyaspora:   president only; same rule as domestic president.
module Election
  class WinnerStampingService
    class Error < StandardError; end

    def self.call(election, stamped_by: nil)
      new(election, stamped_by: stamped_by).call
    end

    def initialize(election, stamped_by: nil)
      @election = election
      @stamped_by = stamped_by
    end

    def call
      raise Error, "Eleksyon dwe fèmen avan sètifikasyon" unless @election.closed?

      winners_written = 0

      ActiveRecord::Base.transaction do
        @election.election_constituencies.find_each do |constituency|
          winners_written += stamp_constituency(constituency)
        end

        @election.update!(status: "certified", certified_at: Time.current)
      end

      { winners_count: winners_written, certified_at: @election.certified_at }
    end

    private

    def stamp_constituency(constituency)
      candidates = constituency.election_candidates
                               .where(status: "active")
                               .order(round_votes_field => :desc)
                               .to_a

      return 0 if candidates.empty?

      total = constituency_total_votes(constituency)
      seats = [constituency.seats.to_i, 1].max

      case constituency.position
      when "president"
        stamp_presidential(constituency, candidates, total)
      when "senator", "deputy"
        stamp_multi_seat(constituency, candidates, total, seats)
      else
        # Unknown position — stamp top-1 as a safe default.
        stamp_multi_seat(constituency, candidates, total, 1)
      end
    end

    # Presidential: skip if no majority and this is round 1 (a runoff will
    # stamp the real winner). Stamp top-1 otherwise.
    def stamp_presidential(constituency, candidates, total)
      top = candidates.first
      top_share = total.zero? ? 0.0 : top.send(round_votes_field).to_f / total

      if @election.round == 1 && top_share <= 0.5
        # Runoff is expected. Don't stamp; BonvoteElection#create_runoff!
        # will spin up a round-2 election and the certify pipeline there
        # will stamp the real winner.
        return 0
      end

      write_winner!(
        constituency:  constituency,
        candidate:     top,
        seat_label:    "president",
        total_votes:   total,
        seat_index:    1
      )
      1
    end

    def stamp_multi_seat(constituency, candidates, total, seats)
      candidates.first(seats).each_with_index.sum do |candidate, i|
        write_winner!(
          constituency: constituency,
          candidate:    candidate,
          seat_label:   seat_label_for(constituency, i + 1),
          total_votes:  total,
          seat_index:   i + 1
        )
        1
      end
    end

    # Generate a stable, human-readable seat label for uniqueness + display.
    def seat_label_for(constituency, seat_index)
      base = constituency.position
      scope = constituency.department_code.presence ||
              constituency.commune_id&.to_s&.then { |id| "commune_#{id}" } ||
              "general"
      seats = constituency.seats.to_i

      if seats > 1
        "#{base}_#{scope.downcase}_seat_#{seat_index}"
      else
        "#{base}_#{scope.downcase}"
      end
    end

    # Total votes cast in this constituency's race. Matches the query shape
    # in BonvoteElection#constituencies_needing_runoff for consistency.
    def constituency_total_votes(constituency)
      scope = @election.election_ballots.where(position: constituency.position)
      scope = scope.where(department_code: constituency.department_code) if constituency.department_code.present?
      scope.count
    end

    def round_votes_field
      @election.round == 2 ? :votes_round2 : :votes_round1
    end

    def write_winner!(constituency:, candidate:, seat_label:, total_votes:, seat_index:)
      votes = candidate.send(round_votes_field).to_i
      share = total_votes.zero? ? nil : (votes.to_f / total_votes).round(4)

      ElectionWinner.create!(
        election:               @election,
        election_constituency:  constituency,
        election_candidate:     candidate,
        seat_label:             seat_label,
        round:                  @election.round || 1,
        vote_count:             votes,
        vote_share:             share,
        total_votes:            total_votes,
        stamped_at:             Time.current,
        stamped_by_admin_user:  @stamped_by
      )

      # Keep the legacy flag in sync for downstream readers that still use it.
      candidate.update_columns(winner: true)
    end
  end
end
