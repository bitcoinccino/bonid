# config/initializers/geocoder.rb
Geocoder.configure(
  timeout: 5,
  lookup: :nominatim, # ✅ Specify the lookup service
  ip_lookup: :ipinfo_io,
  language: :en,
  use_https: true,
  cache: nil,
  cache_prefix: 'geocoder:',
  units: :km,
  http_headers: {
    "User-Agent" => "BonID/1.0 (contact@example.com)" # ✅ REQUIRED by Nominatim
  }
)
