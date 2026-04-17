# config/initializers/geocoder.rb
# frozen_string_literal: true

Geocoder.configure(
  lookup: Rails.env.development? ? :test : :nominatim,
  ip_lookup: :ipinfo_io,
  timeout: 5,
  use_https: true,
  language: :en,
  units: :km,
  cache: Rails.cache,
  cache_prefix: "geocoder:",
  cache_options: { expires_in: 30.days },
  http_headers: {
    "User-Agent" => "BonID/1.0 (support@bonid.ht)"
  }
)

# Disable actual geocoding in development/test
if Rails.env.development? || Rails.env.test?
  Geocoder.configure(lookup: :test)
  Geocoder::Lookup::Test.set_default_stub(
    [
      {
        "coordinates"  => [ 18.5944, -72.3074 ],
        "address"      => "Port-au-Prince, Haiti",
        "city"         => "Port-au-Prince",
        "state"        => "Ouest",
        "country"      => "Haiti",
        "country_code" => "HT"
      }
    ]
  )
end
