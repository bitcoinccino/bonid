# lib/tasks/refactor_banking_agents.rake
namespace :bonid do
  desc "Refactor all banking_agent references to banking_agents and set up teller role invite flow"
  task refactor_banking_agents: :environment do
    puts "🚀 Starting BonID Banking Agent Refactor..."

    replacements = {
      "partner_portal/banking_agent/" => "partner_portal/banking_agents/",
      "partner_portal/banking_agent" => "partner_portal/banking_agents",
      "banking_agent/" => "banking_agents/",
      "banking_agent" => "banking_agents"
    }

    # Target directories
    dirs = %w[
      app/controllers/partner_portal/banking_agent
      app/views/partner_portal/banking_agent
      app/views/layouts/partner_portal/banking_agent.html.erb
    ]

    dirs.each do |path|
      if File.exist?(path)
        new_path = path.gsub("banking_agent", "banking_agents")
        FileUtils.mkdir_p(File.dirname(new_path))
        FileUtils.mv(path, new_path)
        puts "✅ Renamed: #{path} → #{new_path}"
      end
    end

    # Replace contents in relevant files
    files = Dir.glob("app/**/*.{rb,erb,html,js,scss}") +
            Dir.glob("config/**/*.rb")

    files.each do |file|
      text = File.read(file)
      new_text = text.dup
      replacements.each { |old, newv| new_text.gsub!(old, newv) }

      next if text == new_text

      File.write(file, new_text)
      puts "✏️  Updated references in #{file}"
    end

    puts "🎉 Banking Agents pluralization complete!"

    # --- Add Teller role logic if missing ---
    unless Role.exists?(name: "teller")
      Role.create!(name: "teller")
      puts "👤 Created new Role: teller"
    end

    puts "✅ Teller role ensured."
    puts "✅ All done. Restart your server and verify at /banking_agents/sign_in"
  end
end
