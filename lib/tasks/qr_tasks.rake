namespace :bonid do
  desc "Regenerate QR codes for all approved IdentitySubmissions with a user BonID, updating expires_at and verification_token"
  task regenerate_qr_codes: :environment do
    include Rails.application.routes.url_helpers

    # Ensure host comes from ENV, fallback to ngrok if not set
    default_url_options[:host] = ENV.fetch("APP_HOST", "https://3ef64d976dcf.ngrok-free.app")

    puts "🔄 Starting QR code regeneration for approved IdentitySubmissions..."

    IdentitySubmission.approved.includes(:user).find_each do |submission|
      user = submission.user

      unless user&.bonid.present?
        puts "⚠️  Skipping submission ##{submission.id} — user has no BonID"
        next
      end

      begin
        puts "➡️  Updating submission ##{submission.id} (BonID: #{user.bonid})..."

        # Update fields manually
        submission.update_columns(
          verification_token: SecureRandom.hex(16),
          expires_at: 5.minutes.from_now,
          updated_at: Time.current
        )

        # Regenerate the combined QR code (calls internal QR logic)
        submission.regenerate_combined_qr!

        # Generate and display verification link
        verify_url = verify_identity_submission_url(
          verification_token: submission.verification_token
        )
        puts "🔗 Verification URL: #{verify_url}"

        puts "✅  QR code regenerated for submission ##{submission.id}"
      rescue => e
        puts "❌  Submission ##{submission.id} failed: #{e.message}"
        Rails.logger.error "[BonID QR Regeneration] Submission ##{submission.id}: #{e.message}"
      end
    end

    puts "✅ All eligible QR codes processed."
  end
end
