# frozen_string_literal: true

# Mixed in by any model that exposes the GBP-style per-day operating-hours
# editor (ElectoralOffice, ElectionMissionParticipation, …). The host model
# must have a JSONB column called `operating_hours` (default {}, not null)
# and have called `before_validation :normalize_operating_hours` if it
# wants slot cleanup at save time — this concern installs that callback
# automatically when included.
#
# Storage shape (canonical, after normalize):
#
#   {
#     "mon" => [{ "open" => "08:00", "close" => "12:00" },
#               { "open" => "13:00", "close" => "16:00" }],
#     "tue" => [{ "open" => "08:00", "close" => "16:00" }],
#     ...
#   }
#
# Closed days are simply absent from the hash.
module HasOperatingHours
  extend ActiveSupport::Concern

  DAYS = %w[mon tue wed thu fri sat sun].freeze
  DAY_LABELS = {
    "mon" => "Lendi",   "tue" => "Madi",     "wed" => "Mèkredi",
    "thu" => "Jedi",    "fri" => "Vandredi", "sat" => "Samdi",
    "sun" => "Dimanch"
  }.freeze
  DAY_LABELS_SHORT = {
    "mon" => "L", "tue" => "M", "wed" => "Mè", "thu" => "J",
    "fri" => "V", "sat" => "Sd", "sun" => "Dim"
  }.freeze

  included do
    before_validation :normalize_operating_hours
  end

  # Slots for a given day, normalized to an Array of {open,close} hashes.
  # Tolerates three persisted shapes for backward compatibility:
  #   - new shape:   { "mon" => [{ "open" => "08:00", "close" => "12:00" }, ...] }
  #   - legacy v1:   { "mon" => { "open" => "08:00", "close" => "16:00" } }
  #   - empty/absent → []
  def slots_for(day)
    raw = operating_hours&.dig(day.to_s)
    return [] if raw.blank?

    list =
      if raw.is_a?(Hash) && (raw.key?("open") || raw.key?(:open))
        [raw]
      else
        Array(raw)
      end

    list.filter_map do |s|
      o = (s["open"]  || s[:open]).to_s
      c = (s["close"] || s[:close]).to_s
      next if o.blank? || c.blank?
      { "open" => o, "close" => c }
    end
  end

  def open_on?(day)
    slots_for(day).any?
  end

  # One-line display: groups consecutive days with identical hours strings
  # into ranges so the locator reads "L-V 08:00-12:00, 13:00-16:00 · Sd-Dim
  # Fèmen" instead of seven separate lines.
  def display_hours
    rows = DAYS.map do |d|
      slots = slots_for(d)
      txt = slots.empty? ? "Fèmen" : slots.map { |s| "#{s['open']}-#{s['close']}" }.join(", ")
      [DAY_LABELS_SHORT[d], txt]
    end

    runs = rows.slice_when { |a, b| a[1] != b[1] }.map do |run|
      span = run.size == 1 ? run.first[0] : "#{run.first[0]}-#{run.last[0]}"
      "#{span} #{run.first[1]}"
    end
    runs.join(" · ")
  end

  private

  # Strip empty/half-filled slots and convert the form's index-keyed hash
  # (e.g. `{"0" => {...}, "1" => {...}}`, which is how Rails parses
  # `operating_hours[mon][0][open]`) into a clean Array of slots. A slot
  # needs BOTH open and close to survive. Days with zero usable slots are
  # dropped entirely.
  def normalize_operating_hours
    return if operating_hours.blank?

    cleaned = {}
    DAYS.each do |d|
      raw = operating_hours[d] || operating_hours[d.to_sym]
      next if raw.blank?

      candidates =
        if raw.is_a?(Hash) && (raw.key?("open") || raw.key?(:open))
          [raw]
        elsif raw.is_a?(Hash)
          raw.values
        else
          Array(raw)
        end

      slots = candidates.filter_map do |s|
        next unless s.respond_to?(:[])
        o = (s["open"]  || s[:open]).to_s.strip
        c = (s["close"] || s[:close]).to_s.strip
        next if o.blank? || c.blank?
        { "open" => o, "close" => c }
      end

      cleaned[d] = slots if slots.any?
    end
    self.operating_hours = cleaned
  end
end
