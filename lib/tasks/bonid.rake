namespace :bonid do
  # ---------------------------------------------------------------------------
  # Regenerate all existing BonIDs with 2-letter department codes.
  # Old format: DV-1989-M-SUDEST-P-8697-XDS
  # New format: DV-1989-M-SE-P8697XDS
  #
  # Usage:
  #   rails bonid:regenerate_codes           # dry run (preview changes)
  #   rails bonid:regenerate_codes DRY_RUN=0 # apply changes
  # ---------------------------------------------------------------------------
  desc "Regenerate BonIDs with 2-letter department abbreviations"
  task regenerate_codes: :environment do
    dry_run = ENV.fetch("DRY_RUN", "1") != "0"

    puts dry_run ? "🔍 DRY RUN — no changes will be saved" : "🚀 LIVE RUN — updating BonIDs"
    puts "-" * 60

    updated = 0
    skipped = 0
    failed  = 0

    User.where.not(bonid: nil).find_each do |user|
      old_bonid = user.bonid

      begin
        new_bonid = user.generate_bonid!

        if new_bonid == old_bonid
          skipped += 1
        else
          if dry_run
            puts "  #{user.id}: #{old_bonid} → #{new_bonid} (preview)"
            # Revert the change since this is a dry run
            user.update_column(:bonid, old_bonid)
          else
            puts "  ✅ #{user.id}: #{old_bonid} → #{new_bonid}"
          end
          updated += 1
        end
      rescue => e
        puts "  ❌ #{user.id}: #{e.message}"
        # Restore old value on failure
        user.update_column(:bonid, old_bonid) rescue nil
        failed += 1
      end
    end

    puts "-" * 60
    puts "📊 Results: #{updated} updated, #{skipped} unchanged, #{failed} failed"
    puts "💡 Run with DRY_RUN=0 to apply changes" if dry_run
  end

  # ---------------------------------------------------------------------------
  # Generate an Ed25519 keypair for BonID QR code signing.
  #
  # Outputs Base64-encoded private and public keys for ENV vars:
  #   BONID_QR_ED25519_PRIVATE
  #   BONID_QR_ED25519_PUBLIC
  #
  # Usage:
  #   rails bonid:generate_ed25519_keypair
  # ---------------------------------------------------------------------------
  desc "Generate Ed25519 keypair for BonID QR code signing"
  task generate_ed25519_keypair: :environment do
    require "ed25519"
    require "base64"
    require "digest"

    signing_key = Ed25519::SigningKey.generate
    verify_key  = signing_key.verify_key

    private_b64 = Base64.strict_encode64(signing_key.to_bytes)
    public_b64  = Base64.strict_encode64(verify_key.to_bytes)
    fingerprint = Digest::SHA256.hexdigest(verify_key.to_bytes)

    puts "=" * 60
    puts "Ed25519 Keypair for BonID QR Signing"
    puts "=" * 60
    puts
    puts "Add these to your environment (.env, credentials, etc.):"
    puts
    puts "BONID_QR_ED25519_PRIVATE=#{private_b64}"
    puts "BONID_QR_ED25519_PUBLIC=#{public_b64}"
    puts
    puts "Public key fingerprint (SHA-256):"
    puts "  #{fingerprint}"
    puts
    puts "Partners only need the PUBLIC key for offline verification."
    puts "They can fetch it at: GET /api/v1/public_keys/bonid"
    puts "=" * 60
  end

  # ---------------------------------------------------------------------------
  # Re-sign all approved QR codes with Ed25519.
  #
  # Requires BONID_QR_ED25519_PRIVATE / BONID_QR_ED25519_PUBLIC ENV vars.
  #
  # Usage:
  #   rails bonid:regenerate_qr_codes_ed25519           # dry run
  #   rails bonid:regenerate_qr_codes_ed25519 DRY_RUN=0 # apply
  # ---------------------------------------------------------------------------
  desc "Re-sign all approved BonID QR codes with Ed25519"
  task regenerate_qr_codes_ed25519: :environment do
    dry_run = ENV.fetch("DRY_RUN", "1") != "0"

    puts dry_run ? "🔍 DRY RUN — no changes will be saved" : "🚀 LIVE RUN — re-signing QR codes"
    puts "-" * 60

    # Verify keys are available
    begin
      BonidQrSigner.public_key_base64 || raise("Public key not available")
    rescue => e
      puts "❌ Ed25519 keys not configured: #{e.message}"
      puts "   Run: rails bonid:generate_ed25519_keypair"
      exit 1
    end

    updated = 0
    skipped = 0
    failed  = 0

    IdentitySubmission.where(status: :approved).find_each do |submission|
      if submission.user&.bonid.blank?
        skipped += 1
        next
      end

      if dry_run
        puts "  #{submission.id}: #{submission.user.bonid} (would re-sign)"
        updated += 1
      else
        begin
          submission.regenerate_combined_qr!
          puts "  ✅ #{submission.id}: #{submission.user.bonid}"
          updated += 1
        rescue => e
          puts "  ❌ #{submission.id}: #{e.message}"
          failed += 1
        end
      end
    end

    puts "-" * 60
    puts "📊 Results: #{updated} re-signed, #{skipped} skipped, #{failed} failed"
    puts "💡 Run with DRY_RUN=0 to apply changes" if dry_run
  end

  desc "Migrate User.photo into the latest IdentitySubmission.photo"
  task migrate_user_photo_to_submissions: :environment do
    puts "📦 Starting migration of User.photo → IdentitySubmission.photo"

    User.includes(:photo_attachment, :identity_submissions).find_each do |user|
      next unless user.photo.attached?

      latest_submission = user.identity_submissions.order(created_at: :desc).first
      if latest_submission.present?
        if latest_submission.photo.attached?
          puts "⚠️ Skipping User #{user.id} (submission #{latest_submission.id} already has photo)"
        else
          latest_submission.photo.attach(user.photo.blob)
          puts "✅ Migrated User #{user.id} photo → Submission #{latest_submission.id}"
        end
      else
        puts "⏭️ Skipping User #{user.id} (no submissions)"
      end
    end

    puts "🎉 Migration finished!"
  end
end
