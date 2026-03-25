# config/initializers/assets.rb

# --------------------------------------------------
# Add asset paths
# --------------------------------------------------
Rails.application.config.assets.paths << Rails.root.join("app/assets/stylesheets")
Rails.application.config.assets.paths << Rails.root.join("app/assets/fonts")

# Optional: auto-include subfolders (safe)
Dir.glob(Rails.root.join("app/assets/stylesheets/**/*")).each do |path|
  Rails.application.config.assets.paths << path if File.directory?(path)
end

Dir.glob(Rails.root.join("app/assets/fonts/**/*")).each do |path|
  Rails.application.config.assets.paths << path if File.directory?(path)
end

# --------------------------------------------------
# Explicit font precompile (Propshaft-safe)
# --------------------------------------------------
Rails.application.config.assets.precompile += %w[
  glock_grotesque/GlockGrotesque-Medium.woff
  glock_grotesque/GlockGrotesque-Medium.woff2
]

# --------------------------------------------------
# Additional stylesheets (isolated entry points)
# --------------------------------------------------
Rails.application.config.assets.precompile += %w[
  partner_portal_public.css
  officer.css
  visitor.css
]
