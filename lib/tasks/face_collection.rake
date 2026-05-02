# frozen_string_literal: true

# lib/tasks/face_collection.rake
#
# Rake tasks for managing the AWS Rekognition face collection
# used for 1:N identity deduplication.
#
# Setup (run once after deploy):
#   rake face_collection:setup
#
# Bootstrap (index all existing approved users):
#   rake face_collection:bootstrap
#
# Stats:
#   rake face_collection:stats
#
namespace :face_collection do
  desc "Create the Rekognition face collection (run once)"
  task setup: :environment do
    puts "Creating Rekognition collection: #{FaceCollectionService::COLLECTION_ID}..."
    FaceCollectionService.ensure_collection!
    stats = FaceCollectionService.collection_stats
    puts "Collection ready. Current face count: #{stats[:face_count]}"
  end

  desc "Index all approved submissions into the face collection (bootstrap). " \
       "FORCE=1 re-indexes rows whose local metadata claims they're indexed " \
       "but the AWS collection was deleted/recreated since then."
  task bootstrap: :environment do
    FaceCollectionService.ensure_collection!

    force = ENV["FORCE"] == "1"

    submissions = IdentitySubmission
      .where(status: :approved)
      .where.not(user_id: nil)
      .includes(:user)
      .order(:id)

    total = submissions.count
    indexed = 0
    skipped = 0
    failed = 0

    puts "Bootstrapping #{total} approved submissions into face collection#{force ? " (FORCE re-index)" : ""}..."
    puts "Collection: #{FaceCollectionService::COLLECTION_ID}"
    puts "-" * 60

    submissions.find_each(batch_size: 50) do |submission|
      # Skip if already indexed (unless FORCE=1, which assumes AWS state
      # may have drifted from local metadata — e.g. collection rebuilt).
      if !force && submission.metadata&.dig("face_collection", "face_id").present?
        skipped += 1
        next
      end

      # Skip if no selfie
      unless submission.selfie.attached?
        skipped += 1
        print "S"
        next
      end

      begin
        selfie_bytes = submission.selfie.blob.download
        face_id = FaceCollectionService.index(selfie_bytes, submission.user_id)

        if face_id
          current_metadata = submission.metadata || {}
          current_metadata["face_collection"] = {
            "face_id" => face_id,
            "indexed_at" => Time.current.iso8601,
            "collection_id" => FaceCollectionService::COLLECTION_ID,
            "bootstrapped" => true
          }
          submission.update_column(:metadata, current_metadata)
          indexed += 1
          print "."
        else
          skipped += 1
          print "Q" # Quality filter rejected
        end
      rescue StandardError => e
        failed += 1
        print "X"
        Rails.logger.error "[face_collection:bootstrap] Failed for submission ##{submission.id}: #{e.class} - #{e.message}"
      end

      # Rate limit to stay within AWS limits (5 TPS for IndexFaces)
      sleep(0.25)
    end

    puts ""
    puts "-" * 60
    puts "Bootstrap complete!"
    puts "  Indexed: #{indexed}"
    puts "  Skipped: #{skipped} (already indexed, no selfie, or quality filter)"
    puts "  Failed:  #{failed}"
    puts ""

    stats = FaceCollectionService.collection_stats
    puts "Collection now has #{stats[:face_count]} faces."
  end

  desc "Show face collection statistics"
  task stats: :environment do
    stats = FaceCollectionService.collection_stats

    if stats[:exists] == false
      puts "Collection does not exist yet. Run: rake face_collection:setup"
    else
      puts "Face Collection: #{FaceCollectionService::COLLECTION_ID}"
      puts "  Faces indexed: #{stats[:face_count]}"
      puts "  Created at:    #{stats[:created_at]}"
      puts "  Model version: #{stats[:model_version]}"
    end

    # Compare with DB
    approved_count = IdentitySubmission.where(status: :approved).count
    indexed_count = IdentitySubmission
      .where(status: :approved)
      .where("metadata -> 'face_collection' ->> 'face_id' IS NOT NULL")
      .count

    puts ""
    puts "Database:"
    puts "  Approved submissions: #{approved_count}"
    puts "  With face indexed:    #{indexed_count}"
    puts "  Missing from collection: #{approved_count - indexed_count}"
  end

  desc "Remove all faces and delete the collection (DESTRUCTIVE)"
  task destroy: :environment do
    puts "WARNING: This will delete the entire face collection!"
    print "Type 'DELETE' to confirm: "
    confirmation = $stdin.gets&.strip

    unless confirmation == "DELETE"
      puts "Aborted."
      next
    end

    begin
      FaceCollectionService.send(:rekognition_client).delete_collection(
        collection_id: FaceCollectionService::COLLECTION_ID
      )
      puts "Collection #{FaceCollectionService::COLLECTION_ID} deleted."

      # Clear face_collection metadata from all submissions
      IdentitySubmission
        .where("metadata -> 'face_collection' IS NOT NULL")
        .find_each do |sub|
          meta = sub.metadata
          meta.delete("face_collection")
          sub.update_column(:metadata, meta)
        end

      puts "Cleared face_collection metadata from all submissions."
    rescue Aws::Rekognition::Errors::ResourceNotFoundException
      puts "Collection does not exist."
    end
  end
end
