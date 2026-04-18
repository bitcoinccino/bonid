# frozen_string_literal: true

require "csv"

module Election
  # Bulk-imports polling centers (Sant Vòt) and auto-generates their polling
  # stations (BVs) for a given election. Accepts a single CSV that mixes
  # domestic and diaspora centers, keyed by `center_type`.
  #
  # Idempotent: re-running the same CSV is a no-op. A center is matched by
  # (election, name, communal_section_id) for domestic rows, or
  # (election, name, diplomatic_mission_id) for diaspora rows — so corrections
  # to a prior CSV update in place rather than duplicating.
  #
  # Stations are generated as `(total_capacity / 450.0).ceil` BVs. The last BV
  # may have partial capacity. Existing stations are never deleted — that
  # protects voter assignments already made against a previous import.
  #
  # Returns a Result struct describing per-row outcomes. Header errors and
  # per-row errors are both caught so the operator can see exactly which lines
  # failed without aborting the whole upload. Each row runs in its own
  # transaction.
  #
  # Usage:
  #   result = Election::PollingCenterImporter.call(csv_io: uploaded, election: e)
  #   result.centers_created      # => 42
  #   result.stations_created     # => 167
  #   result.errors               # => [{ line: 5, name: "...", message: "..." }]
  class PollingCenterImporter
    REQUIRED_HEADERS = %i[center_type name total_capacity].freeze
    DEFAULT_STATION_CAPACITY = 450

    Result = Struct.new(
      :rows_processed, :centers_created, :centers_updated,
      :stations_created, :errors,
      keyword_init: true
    )

    def self.call(csv_io:, election:)
      new(csv_io: csv_io, election: election).call
    end

    def initialize(csv_io:, election:)
      @csv_io = csv_io
      @election = election
      @result = Result.new(
        rows_processed: 0, centers_created: 0, centers_updated: 0,
        stations_created: 0, errors: []
      )
    end

    def call
      raw = @csv_io.respond_to?(:read) ? @csv_io.read : @csv_io.to_s
      csv = CSV.parse(raw, headers: true, header_converters: :symbol, skip_blanks: true)
      validate_headers!(csv.headers)

      csv.each.with_index(2) do |row, line_no| # line 1 is the header
        process_row(row, line_no)
      end

      @result
    end

    private

    def validate_headers!(headers)
      missing = REQUIRED_HEADERS - headers.compact
      return if missing.empty?

      raise ArgumentError, "CSV missing required headers: #{missing.join(", ")}"
    end

    def process_row(row, line_no)
      @result.rows_processed += 1
      attrs = extract_attrs(row)
      validate_row!(attrs)

      ActiveRecord::Base.transaction do
        center = upsert_center(attrs)
        generate_stations(center, attrs[:total_capacity])
      end
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      @result.errors << { line: line_no, name: row[:name], message: e.message }
    end

    def extract_attrs(row)
      {
        center_type:           row[:center_type]&.downcase&.strip,
        name:                  row[:name]&.strip,
        total_capacity:        row[:total_capacity].to_i,
        priority:              (row[:priority].presence || 0).to_i,
        country_code:          row[:country_code]&.upcase&.strip,
        address_line_1:        row[:address_line_1]&.strip,
        address_line_2:        row[:address_line_2]&.strip,
        city:                  row[:city]&.strip,
        state_province:        row[:state_province]&.strip,
        postal_code:           row[:postal_code]&.strip,
        department_id:         row[:department_id].presence,
        arrondissement_id:     row[:arrondissement_id].presence,
        commune_id:            row[:commune_id].presence,
        communal_section_id:   row[:communal_section_id].presence,
        diplomatic_mission_id: row[:diplomatic_mission_id]&.upcase&.strip.presence,
        contact_phone:         row[:contact_phone]&.strip,
        contact_hours:         row[:contact_hours]&.strip,
        notes:                 row[:notes]&.strip
      }
    end

    def validate_row!(attrs)
      raise ArgumentError, "name required" if attrs[:name].blank?
      raise ArgumentError, "total_capacity must be > 0" if attrs[:total_capacity] <= 0

      case attrs[:center_type]
      when "domestic"
        raise ArgumentError, "domestic row requires communal_section_id" if attrs[:communal_section_id].blank?
        attrs[:country_code] ||= "HT"
      when "diaspora"
        raise ArgumentError, "diaspora row requires diplomatic_mission_id" if attrs[:diplomatic_mission_id].blank?
        raise ArgumentError, "diaspora row requires country_code" if attrs[:country_code].blank?
      else
        raise ArgumentError, "center_type must be 'domestic' or 'diaspora', got #{attrs[:center_type].inspect}"
      end
    end

    def upsert_center(attrs)
      scope = @election.polling_centers.where(name: attrs[:name])
      scope = if attrs[:center_type] == "domestic"
                scope.where(communal_section_id: attrs[:communal_section_id])
              else
                scope.where(diplomatic_mission_id: attrs[:diplomatic_mission_id])
              end

      center = scope.first_or_initialize
      was_new = center.new_record?

      center.assign_attributes(
        center_type:           attrs[:center_type],
        priority:              attrs[:priority],
        country_code:          attrs[:country_code],
        address_line_1:        attrs[:address_line_1],
        address_line_2:        attrs[:address_line_2],
        city:                  attrs[:city],
        state_province:        attrs[:state_province],
        postal_code:           attrs[:postal_code],
        department_id:         attrs[:department_id],
        arrondissement_id:     attrs[:arrondissement_id],
        commune_id:            attrs[:commune_id],
        communal_section_id:   attrs[:communal_section_id],
        diplomatic_mission_id: attrs[:diplomatic_mission_id],
        contact_phone:         attrs[:contact_phone],
        contact_hours:         attrs[:contact_hours],
        notes:                 attrs[:notes]
      )
      # Centers imported into an already-open election must be immediately
      # usable for voter assignment — the assignment scope filters on
      # `polling_centers.status = "open"`, so "planned" would silently
      # exclude them. For draft elections we keep "planned" so the CEP can
      # review the roster before activating it.
      if center.status.blank?
        center.status = @election.status == "open" ? "open" : "planned"
      end
      center.save!

      if was_new
        @result.centers_created += 1
      else
        @result.centers_updated += 1
      end

      center
    end

    # Creates any missing BV rows. Never deletes or edits existing BVs —
    # they may already have voters assigned, and capacity-shrinking would be
    # destructive. Operators who need to change capacity should do it manually.
    def generate_stations(center, total_capacity)
      num_stations = (total_capacity.to_f / DEFAULT_STATION_CAPACITY).ceil
      existing_bvs = center.polling_stations.pluck(:bv_number).to_set

      (1..num_stations).each do |bv|
        next if existing_bvs.include?(bv)

        # Last BV may be partial; all others are full 450.
        capacity = if bv == num_stations
                     remainder = total_capacity - (DEFAULT_STATION_CAPACITY * (num_stations - 1))
                     remainder.positive? ? remainder : DEFAULT_STATION_CAPACITY
                   else
                     DEFAULT_STATION_CAPACITY
                   end

        center.polling_stations.create!(
          bv_number: bv,
          capacity: capacity,
          registered_count: 0,
          status: "open"
        )
        @result.stations_created += 1
      end
    end
  end
end
