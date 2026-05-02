# frozen_string_literal: true

# lib/tasks/identity_audit.rake
#
# Audit existing IdentitySubmission rows for duplicates and gaps in the
# fraud-prevention layers. Read-only — does not modify data.
#
# Layer 1 — Document-number uniqueness (model-level validator):
#   Finds rows where the same `document_number` exists across DIFFERENT
#   `user_id`s in approved/pending status. These should never have
#   coexisted; if they do, the validator was bypassed at some point.
#
# Layer 2 — Face dedup (AWS Rekognition collection):
#   Finds approved submissions missing the `metadata.face_collection`
#   index entry. Faces not in the collection can't be matched against
#   future submissions, so any future signup using their face slips
#   through. Bootstrap them with `rake face_collection:bootstrap`.
#
# Usage:
#   bin/rails identity_audit:duplicates           # Layer 1 audit
#   bin/rails identity_audit:face_index_gaps      # Layer 2 audit
#   bin/rails identity_audit:full                 # both
#
namespace :identity_audit do
  desc "List IdentitySubmissions with duplicate document_number across different users"
  task duplicates: :environment do
    puts "─" * 78
    puts "LAYER 1 AUDIT — Document-number duplicates across user accounts"
    puts "─" * 78

    # Find document_numbers that appear on multiple user_ids in approved/pending
    duplicate_numbers = IdentitySubmission
      .where(status: %i[approved pending])
      .where.not(document_number: [ nil, "" ])
      .group(:document_number)
      .having("COUNT(DISTINCT user_id) > 1")
      .pluck(:document_number)

    if duplicate_numbers.empty?
      puts ""
      puts "✅ No document-number duplicates found across users."
      puts ""
      next
    end

    puts ""
    puts "⚠️  Found #{duplicate_numbers.size} document number(s) shared across multiple accounts:"
    puts ""

    duplicate_numbers.each do |doc_num|
      subs = IdentitySubmission
        .where(document_number: doc_num, status: %i[approved pending])
        .includes(:user)
        .order(:verified_at, :created_at)

      printf "  Document: %-20s  (%d submissions)\n", doc_num, subs.count
      subs.each do |s|
        email = s.user&.email || "(no user)"
        verified = s.verified_at&.strftime("%Y-%m-%d") || "—"
        printf "    sub_id=%-6d user_id=%-5d status=%-8s verified=%-10s email=%s\n",
               s.id, s.user_id, s.status, verified, email
      end
      puts ""
    end

    puts "─" * 78
    puts "Action: revoke or merge the duplicates manually after reviewer audit."
    puts "        On revoke, IdentitySubmission#index_face_in_collection cleanup"
    puts "        also removes that face from the AWS collection."
    puts "─" * 78
  end

  desc "List approved IdentitySubmissions missing from the AWS face collection"
  task face_index_gaps: :environment do
    puts "─" * 78
    puts "LAYER 2 AUDIT — Approved BonIDs missing from AWS face collection"
    puts "─" * 78

    approved_count = IdentitySubmission.where(status: :approved).count
    indexed_count  = IdentitySubmission
      .where(status: :approved)
      .where("metadata -> 'face_collection' ->> 'face_id' IS NOT NULL")
      .count
    missing = approved_count - indexed_count

    puts ""
    printf "  Total approved BonIDs:   %d\n", approved_count
    printf "  Indexed in collection:   %d\n", indexed_count
    printf "  Missing from collection: %d\n", missing
    puts ""

    if missing.zero?
      puts "✅ Every approved BonID is indexed. Layer 2 fully covered."
      puts ""
      next
    end

    gaps = IdentitySubmission
      .where(status: :approved)
      .where("metadata -> 'face_collection' ->> 'face_id' IS NULL")
      .includes(:user)
      .order(:verified_at)
      .limit(50)

    puts "⚠️  First #{gaps.size} approved submissions WITHOUT face indexing:"
    puts ""
    gaps.each do |s|
      email = s.user&.email || "(no user)"
      verified = s.verified_at&.strftime("%Y-%m-%d") || "—"
      selfie = s.selfie.attached? ? "✓" : "✗"
      printf "    sub_id=%-6d user_id=%-5d verified=%-10s selfie=%s  email=%s\n",
             s.id, s.user_id, verified, selfie, email
    end

    puts ""
    puts "─" * 78
    puts "Fix: bin/rails face_collection:bootstrap"
    puts "     Idempotent — re-running it skips submissions already indexed."
    puts "─" * 78
  end

  desc "Run all identity audits (Layer 1 + Layer 2)"
  task full: %i[duplicates face_index_gaps]
end
