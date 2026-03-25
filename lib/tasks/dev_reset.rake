namespace :dev do
  desc "Nuke all app data (dangerous!)"
  task nuke: :environment do
    puts "🔥 Deleting everything..."

    models = [
      QrScanLog, QrScan, IncidentReport,
      IdentitySubmission, Officer, User, Partner
    ]

    models.each do |model|
      model.delete_all
      puts "✅ Cleared #{model.name}"
    end

    puts "🚨 All data wiped."
  end
end
