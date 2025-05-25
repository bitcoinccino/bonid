# config/initializers/assets.rb

Rails.application.config.assets.version = "1.0"

# 👉 Ensure builds (esbuild & cssbundling) are available
Rails.application.config.assets.paths << Rails.root.join("app/assets/builds")

# 👉 Include node_modules for Bootstrap & icons
Rails.application.config.assets.paths << Rails.root.join("node_modules")
Rails.application.config.assets.paths << Rails.root.join("node_modules/bootstrap-icons/font")

# 👉 Optional: preload specific JS (if using importmap — you're not anymore)
# Rails.application.config.assets.precompile += %w( bootstrap.min.js popper.js bootstrap.bundle.min.js )

# 👉 Include custom image path (good for logos etc.)
Rails.application.config.assets.paths << Rails.root.join("app/assets/images")
