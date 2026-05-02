# frozen_string_literal: true

# lib/tasks/citizen_admin.rake
#
# Hard-delete a citizen user and all their owned data. Intended for dev /
# test cleanup or for honoring legal data-erasure requests in production.
#
# Steps:
#   1. Look up the user by exact email (case-insensitive match).
#   2. Print every record that will be cascade-deleted.
#   3. Remove every approved/pending submission's face_id from the AWS
#      Rekognition collection so future signups don't hit a stale match.
#   4. user.destroy → cascades through dependent: :destroy associations.
#
# Usage:
#   bin/rails citizen_admin:delete EMAIL=user@example.com
#       → preview only (no changes).
#
#   bin/rails citizen_admin:delete EMAIL=user@example.com CONFIRM=YES
#       → actually delete.
#
namespace :citizen_admin do
  desc "Hard-delete a citizen and all their data. CONFIRM=YES to actually delete; otherwise dry-run."
  task delete: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    if email.empty?
      puts "❌ Pass EMAIL=<address> on the command line."
      exit 1
    end

    user = User.where("LOWER(email) = ?", email).first
    if user.nil?
      puts "❌ No user found for email: #{email}"
      puts ""
      similar = User.where("email ILIKE ?", "%#{email.split('@').first.first(5)}%").limit(10)
      if similar.any?
        puts "Similar emails:"
        similar.each { |u| puts "   - #{u.email}  (id=#{u.id})" }
      end
      exit 1
    end

    confirm = ENV["CONFIRM"] == "YES"

    submissions = user.identity_submissions.to_a
    consents    = user.consent_grants.to_a
    txns        = user.transaction_consents.to_a
    apps        = user.service_applications.to_a
    sessions    = user.respond_to?(:citizen_sessions) ? user.citizen_sessions.to_a : []
    bank        = user.respond_to?(:bank_profiles)    ? user.bank_profiles.to_a    : []
    family      = user.respond_to?(:family_members)   ? user.family_members.to_a   : []
    emergency   = user.respond_to?(:emergency_contacts) ? user.emergency_contacts.to_a : []

    puts "─" * 70
    puts confirm ? "🚨 DELETING citizen and all owned records" : "🔍 DRY RUN — pass CONFIRM=YES to actually delete"
    puts "─" * 70
    puts "  User id:   #{user.id}"
    puts "  Email:     #{user.email}"
    puts "  Created:   #{user.created_at}"
    puts "  BonID:     #{user.bonid || '—'}"
    puts ""
    puts "  Cascade:"
    printf "    %-30s %d\n", "identity_submissions",   submissions.size
    printf "    %-30s %d\n", "consent_grants",         consents.size
    printf "    %-30s %d\n", "transaction_consents",   txns.size
    printf "    %-30s %d\n", "service_applications",   apps.size
    printf "    %-30s %d\n", "citizen_sessions",       sessions.size
    printf "    %-30s %d\n", "bank_profiles",          bank.size
    printf "    %-30s %d\n", "family_members",         family.size
    printf "    %-30s %d\n", "emergency_contacts",     emergency.size

    # Surface AWS Rekognition face_ids that would be removed
    indexed_face_ids = submissions
      .filter_map { |s| s.metadata&.dig("face_collection", "face_id") }
    puts ""
    puts "  AWS Rekognition faces to remove from collection: #{indexed_face_ids.size}"
    indexed_face_ids.each { |fid| puts "    - #{fid}" }
    puts "─" * 70

    unless confirm
      puts "✋  Dry run only. Re-run with CONFIRM=YES to execute."
      exit 0
    end

    # 1) Remove faces from the AWS Rekognition collection so future signups
    # don't get auto-rejected against a face whose owner is gone.
    indexed_face_ids.each do |face_id|
      begin
        FaceCollectionService.remove(face_id)
      rescue StandardError => e
        warn "  ⚠️  Failed to remove face_id=#{face_id}: #{e.class} - #{e.message}"
      end
    end

    # 2) Destroy the user (cascade via dependent: :destroy associations).
    ActiveRecord::Base.transaction do
      user.destroy!
    end

    puts ""
    puts "✅ User ##{user.id} (#{email}) deleted."
  end
end
