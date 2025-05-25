namespace :bonid do
  desc "Regenerate JSON-based QR codes for all verified identity submissions"
  task regenerate_qr_codes: :environment do
    puts "🔄 Regenerating QR codes for verified identity submissions..."

    count = 0
    IdentitySubmission.includes(:user, :partner).where(status: :approved).find_each do |submission|
      begin
        submission.regenerate_combined_qr!
        print "."
        count += 1
      rescue => e
        puts "\n⚠️ Failed for submission ID #{submission.id}: #{e.message}"
      end
    end

    puts "\n✅ Done. Regenerated #{count} QR codes."
  end
end


