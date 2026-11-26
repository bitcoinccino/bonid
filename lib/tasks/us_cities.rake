# frozen_string_literal: true

# Builds config/data/us_cities.json ({ "FL" => ["Alachua", ...], ... }) from
# the US Census Bureau Gazetteer "Places" file (public domain):
#   https://www.census.gov/geographies/reference-files/time-series/geo/gazetteer-files.html
#   e.g. 2024_Gaz_place_national.txt (tab-separated, NAME column like "Miami city")
#
#   bin/rails "us_cities:import[/path/to/2024_Gaz_place_national.txt]"
namespace :us_cities do
  # Census legal/statistical descriptors appended to place names
  SUFFIX_WORDS = [
    "CDP", "city and borough", "city", "town", "village", "borough", "municipality",
    "metro township", "unified government", "consolidated government",
    "metropolitan government", "metro government", "urban county", "corporation",
    "comunidad", "zona urbana"
  ].freeze
  SUFFIX = /\s+(?:#{SUFFIX_WORDS.map { |w| Regexp.escape(w) }.join("|")})(?:\s+\(balance\))?\z|\s+\(balance\)\z/

  desc "Build config/data/us_cities.json from a Census Gazetteer places file"
  task :import, [:path] => :environment do |_t, args|
    path = args[:path].presence or abort "Usage: bin/rails \"us_cities:import[/path/to/Gaz_place_national.txt]\""
    states = DiasporaLocations.states.keys
    cities = Hash.new { |h, k| h[k] = Set.new }

    File.foreach(path, encoding: "bom|utf-8").with_index do |line, i|
      next if i.zero? # header
      usps, _geoid, _ansi, name = line.split("\t", 5)
      next unless states.include?(usps)

      clean = name.to_s.strip.sub(SUFFIX, "").strip
      cities[usps] << clean if clean.present?
    end

    data = states.sort.to_h { |code| [code, cities[code].to_a.sort_by { |n| [I18n.transliterate(n).downcase, n] }] }
    out = Rails.root.join(DiasporaLocations::CITY_DATA_PATH)
    File.write(out, JSON.generate(data))
    total = data.values.sum(&:size)
    puts "Wrote #{total} places across #{data.size} states to #{out.relative_path_from(Rails.root)} (#{(File.size(out) / 1024.0).round} KB)"
  end
end
