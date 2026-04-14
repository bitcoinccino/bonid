# frozen_string_literal: true

class IpGeolocator
  def self.locate(ip)
    return nil if ip.blank?

    Rails.cache.fetch("geo:ip:#{ip}", expires_in: 30.days) do
      Geocoder.search(ip).first
    end
  rescue => e
    Rails.logger.warn("[IpGeolocator] Lookup failed for #{ip}: #{e.message}")
    nil
  end

  def self.country_code(ip)
    locate(ip)&.country_code
  end
end
