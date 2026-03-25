# lib/tasks/signatures.rake
namespace :signatures do
  desc "Backfill signatures from existing attachments"
  task backfill: :environment do
    puts "🔁 Starting backfill of signatures..."

    IdentitySubmission.find_each do |submission|
      begin
        puts "➡️  Processing submission ##{submission.id} (user_id=#{submission.user_id})..."

        # ✅ Skip if there's already a signature hash or verified signature
        next if submission.signature_hash.present? || submission.signature_verified_at.present?

        # ✅ Skip if no signature attached
        unless submission.signature.attached?
          puts "⚠️ No signature attached for submission ##{submission.id}, skipping."
          next
        end

        # ✅ Compute hash safely
        io = submission.signature.download
        signature_hash = Digest::SHA256.hexdigest(io)
        submission.update!(
          signature_hash: signature_hash,
          signature_metadata: {
            backfilled_at: Time.current,
            source: "rake:signatures:backfill"
          }
        )

        puts "✅ Signature hash stored for submission ##{submission.id}"
      rescue => e
        puts "⚠️ Failed for submission ##{submission.id}: #{e.message}"
        next
      end
    end

    puts "🎯 Signature backfill completed."
  end
end
