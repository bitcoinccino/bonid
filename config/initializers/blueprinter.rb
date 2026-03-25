# config/initializers/blueprinter.rb
Blueprinter.configure do |config|
  config.generator = JSON    # ✅ use built-in JSON instead of Oj
  config.sort_fields_by = :definition
end
