# app/services/report_id_generator.rb
# Scalable report ID generation without collision risk
class ReportIdGenerator
  # Format: PNH-{UNIT}-{CRIME_CODE}-{YYYYMMDD}-{SEQUENCE}
  # Example: PNH-DCPJ-HOMO-20260208-000001

  LOCK_KEY = "incident_report_id_lock"

  class << self
    def generate(incident_report)
      unit_code = extract_unit_code(incident_report.officer)
      crime_code = extract_crime_code(incident_report.crime_type)
      date_str = (incident_report.occurred_at || Time.current).strftime("%Y%m%d")

      sequence = next_sequence(date_str)

      "PNH-#{unit_code}-#{crime_code}-#{date_str}-#{sequence}"
    end

    private

    def extract_unit_code(officer)
      return "GEN" unless officer&.unit_type.present?

      # Normalize unit to 4-char code
      officer.unit_type
             .gsub(/[^A-Za-z0-9]/, "")
             .upcase
             .slice(0, 4)
             .ljust(4, "X")
    end

    def extract_crime_code(crime_type)
      return "UNKN" unless crime_type.present?

      key = crime_type.downcase.gsub(/[^a-z\s]/, "").strip
      IncidentReport::CRIME_CODES[key] || "UNKN"
    end

    def next_sequence(date_str)
      # Use Redis for atomic sequence generation if available
      if defined?(Redis) && Rails.application.config.respond_to?(:redis)
        redis_sequence(date_str)
      else
        database_sequence(date_str)
      end
    end

    def redis_sequence(date_str)
      key = "incident_seq:#{date_str}"
      redis = Rails.application.config.redis

      # Atomic increment, expires at end of day
      seq = redis.incr(key)
      redis.expireat(key, Date.tomorrow.beginning_of_day.to_i) if seq == 1

      seq.to_s.rjust(6, "0")
    end

    def database_sequence(date_str)
      # Fallback: Use database counter with advisory lock
      ActiveRecord::Base.transaction do
        # Acquire lock for this date
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(#{date_str.to_i})"
        )

        # Count existing reports for this date
        count = IncidentReport
          .where("report_id LIKE ?", "PNH-%-#{date_str}-%")
          .count

        (count + 1).to_s.rjust(6, "0")
      end
    end
  end
end
