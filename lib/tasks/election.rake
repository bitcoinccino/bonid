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

  desc "Load Haiti administrative hierarchy (departments, arrondissements, communes, communal sections) from db/data CSVs. Idempotent — skips rows that already exist. Does NOT destroy any data."
  task load_haiti_geography: :environment do
    require "csv"

    puts "Loading departments..."
    CSV.foreach(Rails.root.join("db/data/departments.csv"), headers: true) do |row|
      Department.find_or_create_by!(id: row["id"].to_i) do |d|
        d.name = row["department_name"]
        d.postal_code_prefix = row["postal_code_prefix"]
      end
    end
    puts "  → #{Department.count} departments"

    puts "Loading arrondissements..."
    CSV.foreach(Rails.root.join("db/data/arrondissements.csv"), headers: true) do |row|
      Arrondissement.find_or_create_by!(id: row["id"].to_i) do |a|
        a.name          = row["arrondissement_name"]
        a.department_id = row["department_id"].to_i
        a.code          = row["postal_code_prefix"]
      end
    end
    puts "  → #{Arrondissement.count} arrondissements"

    puts "Loading communes..."
    dept_by_arrondissement = Arrondissement.all.index_by(&:id).transform_values(&:department_id)
    CSV.foreach(Rails.root.join("db/data/communes.csv"), headers: true) do |row|
      arrondissement_id = row["arrondissement_id"].to_i
      Commune.find_or_create_by!(id: row["id"].to_i) do |c|
        c.code              = row["commune_id"]
        c.name              = row["commune_name"]
        c.arrondissement_id = arrondissement_id
        c.postal_code       = row["postal_code_prefix"]
        c.department_id     = dept_by_arrondissement[arrondissement_id]
      end
    end
    puts "  → #{Commune.count} communes"

    puts "Loading communal sections..."
    commune_code_to_id = Commune.all.index_by(&:code).transform_values(&:id)
    CSV.foreach(Rails.root.join("db/data/communal_sections.csv"), headers: true) do |row|
      next if row["postal_code"].blank? || row["commune_id"].blank?

      commune_id = commune_code_to_id[row["commune_id"]]
      next unless commune_id

      CommunalSection.find_or_create_by!(id: row["id"].to_i) do |s|
        s.name        = row["section_name"]
        s.commune_id  = commune_id
        s.postal_code = row["postal_code"]
      end
    end
    puts "  → #{CommunalSection.count} communal sections"

    puts "Done. Haiti administrative hierarchy is loaded."
  end

  desc "Generate an Ed25519 signing keypair for BonVote-signed voter receipts. Emits YAML ready to paste into `rails credentials:edit`."
  task :generate_signing_keys, [ :election_id ] => :environment do |_, args|
    require "openssl"
    require "base64"

    election_id = args[:election_id].to_s.presence ||
                  BonvoteElection.order(created_at: :desc).first&.id.to_s

    if election_id.blank?
      abort "No election found. Pass an election_id: rails \"election:generate_signing_keys[1]\""
    end

    key    = OpenSSL::PKey.generate_key("ED25519")
    priv64 = Base64.strict_encode64(key.raw_private_key)
    pub64  = Base64.strict_encode64(key.raw_public_key)

    puts <<~YAML

      # Paste the following under your :election key in credentials.yml.enc
      # via `EDITOR="code --wait" bin/rails credentials:edit`.
      # DO NOT commit the private key to version control.

      election:
        bonvote_signing_keys:
          "#{election_id}":
            private: #{priv64}
            public:  #{pub64}

      # Public key (safe to distribute to tablets / observer verifiers):
      # #{pub64}
    YAML

    puts "# Test after install:"
    puts "#   rec = VoterEligibilityRecord.where(bonvote_election_id: #{election_id}).last"
    puts "#   rec.stamp_bonvote_signature!"
    puts "#   rec.reload.bonvote_signature.present? # => true"
  end
end
