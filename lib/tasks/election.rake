# frozen_string_literal: true

namespace :election do
  desc "Seed Haiti 2026 general election (constituencies + placeholder candidates)"
  task seed_2026: :environment do
    puts "Creating Haiti 2026 General Election..."

    election = BonvoteElection.find_or_create_by!(
      election_type: "general",
      round: 1,
      election_date: Date.new(2026, 8, 30)
    ) do |e|
      e.title = "Eleksyon Jeneral Ayiti 2026 — Round 1"
      e.status = "draft"
    end

    puts "  Election: #{election.title} (id=#{election.id})"

    # Seed constituencies (1 president + 10 senate + deputies)
    if election.election_constituencies.empty?
      ElectionConstituency.seed_haiti_2026!(election, senate_seats_up: 1)
      puts "  Constituencies: #{election.election_constituencies.count} created"
    else
      puts "  Constituencies: #{election.election_constituencies.count} (already exist)"
    end

    # Seed electoral bodies (BED/BEC hierarchy)
    if election.election_bodies.empty?
      ElectionBody.seed_haiti_2026!(election)
      puts "  Electoral bodies: #{election.election_bodies.beds.count} BED, #{election.election_bodies.becs.count} BEC"
    else
      puts "  Electoral bodies: #{election.election_bodies.count} (already exist)"
    end

    puts "Done. Use `rake election:import_candidates` to load CEP candidate data."
  end

  desc "Import candidates from CEP CSV file"
  task import_candidates: :environment do
    # Usage: rake election:import_candidates FILE=path/to/candidates.csv ELECTION_ID=1
    #
    # CSV format:
    #   position,full_name,party_name,party_acronym,department_code,commune_id,ballot_number
    #   president,Jean Pierre,Pati Ayisyen,PA,,, 1
    #   senator,Marie Joseph,Fanmi Lavalas,FL,OU,,2
    #   deputy,Paul Dupont,PHTK,PHTK,OU,42,1
    #
    require "csv"

    file = ENV["FILE"]
    election_id = ENV["ELECTION_ID"]

    unless file && File.exist?(file)
      puts "Usage: rake election:import_candidates FILE=candidates.csv ELECTION_ID=1"
      exit 1
    end

    election = BonvoteElection.find(election_id)
    count = 0

    CSV.foreach(file, headers: true, header_converters: :symbol) do |row|
      constituency = election.election_constituencies.find_by(
        position: row[:position],
        department_code: row[:department_code].presence,
        commune_id: row[:commune_id].presence
      )

      # Fall back to position-only match for president
      constituency ||= election.election_constituencies.find_by(position: row[:position]) if row[:position] == "president"

      unless constituency
        puts "  SKIP: No constituency for #{row[:position]} dept=#{row[:department_code]} commune=#{row[:commune_id]}"
        next
      end

      ElectionCandidate.find_or_create_by!(
        election: election,
        election_constituency: constituency,
        full_name: row[:full_name]
      ) do |c|
        c.position = row[:position]
        c.party_name = row[:party_name]
        c.party_acronym = row[:party_acronym]
        c.department_code = row[:department_code]
        c.commune_id = row[:commune_id]
        c.ballot_number = row[:ballot_number]
        c.status = "active"
      end
      count += 1
    end

    puts "Imported #{count} candidates for '#{election.title}'"
  end

  desc "Open an election for voting"
  task open: :environment do
    election = BonvoteElection.find(ENV["ELECTION_ID"])
    election.open!
    puts "Election '#{election.title}' is now OPEN for voting."
  end

  desc "Close an election (no more votes accepted)"
  task close: :environment do
    election = BonvoteElection.find(ENV["ELECTION_ID"])
    election.close!
    puts "Election '#{election.title}' is now CLOSED."
  end

  desc "Check which constituencies need a runoff and create round 2"
  task create_runoff: :environment do
    election = BonvoteElection.find(ENV["ELECTION_ID"])
    runoff_date = Date.parse(ENV["RUNOFF_DATE"] || (election.election_date + 30).to_s)

    needs = election.constituencies_needing_runoff
    if needs.empty?
      puts "No runoff needed — all constituencies have a majority winner."
    else
      puts "#{needs.size} constituency(ies) need a runoff."
      r2 = election.create_runoff!(runoff_date: runoff_date)
      puts "Round 2 created: '#{r2.title}' on #{r2.election_date} (id=#{r2.id})"
      puts "  Constituencies: #{r2.election_constituencies.count}"
      puts "  Candidates: #{r2.election_candidates.count}"
    end
  end

  desc "Show election stats"
  task stats: :environment do
    election = BonvoteElection.find(ENV["ELECTION_ID"])
    stats = ElectionBallot.stats(election.id)

    puts "=== #{election.title} ==="
    puts "  Status: #{election.status}"
    puts "  Total votes: #{stats[:total_votes]}"
    puts "  Remote: #{stats[:remote_votes]}"
    puts "  Consulate: #{stats[:consulate_votes]}"
    puts "  Flagged: #{stats[:flagged]}"
    puts "  By position: #{stats[:by_position]}"
    puts "  By department: #{stats[:by_department]}"
    puts "  Multi-sig: #{ElectionSignature.status_for(election.id)[:total]}/#{ElectionSignature::QUORUM} signatures"
  end
end
