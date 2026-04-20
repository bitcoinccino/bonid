# frozen_string_literal: true

require "csv"

# Imports a batch of paper-petition rows (Article 181.15) into
# ElectionCandidateEndorsement as `source: "csv"` rows.
#
# Expected CSV columns (header required):
#   cin_number           — CIN on the paper petition (required)
#   full_name            — optional, recorded in `notes` for audit
#   signature_image_url  — optional, URL of a scanned signature
#   notes                — optional free-text
#
# Matching logic:
#   1. We look up a voter with this CIN in VoterEligibilityRecord.
#      If found, we stamp the row with that voter's `bonid` and mark it
#      `voter_roll_verified: true`. These count toward the 2% threshold.
#   2. If no voter is found, the row is still stored but left
#      `voter_roll_verified: false` — CEP can review and manually verify
#      against paper rolls.
#
# Dedupe:
#   - Rows whose BonID is already endorsing this candidate are skipped.
#   - Rows whose CIN is already in the import (within the same file) are
#     collapsed to the first occurrence.
module Election
  class EndorsementCsvImporter
    Result = Struct.new(:imported, :verified, :unverified, :duplicates, :errors, keyword_init: true)

    def initialize(candidate:, csv_io:, admin:)
      @candidate = candidate
      @csv_io = csv_io
      @admin = admin
    end

    def call
      imported   = 0
      verified   = 0
      unverified = 0
      duplicates = 0
      errors     = []
      seen_cins  = Set.new

      CSV.foreach(@csv_io, headers: true, header_converters: :downcase) do |row|
        cin = row["cin_number"].to_s.strip
        next if cin.blank?

        if seen_cins.include?(cin)
          duplicates += 1
          next
        end
        seen_cins << cin

        voter = VoterEligibilityRecord.where(cin_number: cin).first
        bonid = voter&.bonid
        verified_flag = voter.present?

        # Skip if already endorsed via BonID
        if bonid.present? &&
           ElectionCandidateEndorsement.exists?(election_candidate_id: @candidate.id, bonid: bonid)
          duplicates += 1
          next
        end

        # Skip if already endorsed via CIN (no-bonid rows)
        if bonid.blank? &&
           ElectionCandidateEndorsement.exists?(election_candidate_id: @candidate.id, cin_number: cin, bonid: nil)
          duplicates += 1
          next
        end

        record = ElectionCandidateEndorsement.new(
          election_candidate: @candidate,
          election: @candidate.election,
          bonid: bonid,
          cin_number: cin,
          source: "csv",
          voter_roll_verified: verified_flag,
          uploaded_by: @admin,
          signature_image_url: row["signature_image_url"].to_s.strip.presence,
          notes: [ row["full_name"], row["notes"] ].compact_blank.join(" — ").presence
        )

        if record.save
          imported += 1
          verified_flag ? (verified += 1) : (unverified += 1)
        else
          errors << "CIN #{cin}: #{record.errors.full_messages.to_sentence}"
        end
      end

      Result.new(
        imported: imported,
        verified: verified,
        unverified: unverified,
        duplicates: duplicates,
        errors: errors
      )
    rescue CSV::MalformedCSVError => e
      Result.new(imported: 0, verified: 0, unverified: 0, duplicates: 0, errors: [ "CSV envalid: #{e.message}" ])
    end
  end
end
