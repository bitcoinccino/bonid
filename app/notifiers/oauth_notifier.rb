# app/notifiers/oauth_notifier.rb
class OauthNotifier
  require "net/http"
  require "json"

  # Sends event to the partner
  # Tries webhook first, falls back to email if webhook not present
  def self.send_event(partner, event)
    if partner.callback_url.present?
      send_webhook(partner.callback_url, event)
    elsif partner.email.present?
      send_email(partner, event)
    else
      raise "No callback URL or email defined for partner #{partner.id}"
    end
  end

  private_class_method

  # POST the event payload to the partner's webhook
  def self.send_webhook(url, event)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = event.payload.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(req)
    end

    unless res.is_a?(Net::HTTPSuccess)
      raise "Webhook failed with status #{res.code}: #{res.body}"
    end

    Rails.logger.info("[OauthNotifier] Event ##{event.id} sent to webhook #{url}")
  end

  # Send the event via email using ApplicationMailer
  def self.send_email(partner, event)
    OauthEventMailer.send_event(partner, event).deliver_now
  end
end
