# Disable ngrok host override in development.
# Host and protocol must be controlled by config/environments/development.rb.
return if Rails.env.development?

require "uri"

if ENV["NGROK_HOST"].present?
  uri = URI.parse(ENV["NGROK_HOST"].include?("://") ? ENV["NGROK_HOST"] : "https://#{ENV["NGROK_HOST"]}")

  Rails.application.routes.default_url_options[:host] = uri.host
  Rails.application.routes.default_url_options[:protocol] = uri.scheme
  Rails.application.routes.default_url_options[:port] = nil if [ 80, 443 ].include?(uri.port)

  Rails.application.config.action_mailer.default_url_options = Rails.application.routes.default_url_options
  Rails.application.config.bonid_base_url = "#{uri.scheme}://#{uri.host}"
end
