module Officers
  class DashboardController < Officers::BaseController
    before_action :authenticate_officer!
    before_action :require_verified_officer!
    before_action :set_counts, only: [:index, :drafts]

    def index
      @draft_reports = current_officer.incident_reports.status_draft.order(created_at: :desc)
      # Load hot zone data for dashboard
      load_hot_zone_data
    end

    def drafts
      @draft_reports = current_officer.incident_reports.status_draft.order(created_at: :desc)

      if turbo_frame_request?
        render partial: "officers/dashboard/drafts", locals: { draft_reports: @draft_reports }, layout: false
      else
        render :drafts
      end
    end

    def crime_reports
      # Scoped to what this officer may see (unit + rank + JTF override)
      @incident_reports = current_officer.effective_incident_reports.includes(:person_involvements)

      if turbo_frame_request?
        render partial: "officers/dashboard/crime_reports", locals: { incident_reports: @incident_reports }, layout: false
      else
        render :crime_reports
      end
    rescue => e
      handle_error(e, "crime_reports")
    end

    def recent_scans
      @recent_scans = current_officer.qr_scans
                                     .includes(identity_submission: :user)
                                     .order(created_at: :desc)
                                     .limit(10)

      if turbo_frame_request?
        render partial: "officers/dashboard/recent_scans", locals: { recent_scans: @recent_scans }, layout: false
      else
        render :recent_scans
      end
    rescue => e
      handle_error(e, "recent_scans")
    end

    def failed_scans
      @failed_scans = current_officer.failed_bonid_lookups
                                     .order(created_at: :desc)
                                     .limit(10)

      if turbo_frame_request?
        render partial: "officers/dashboard/failed_scans", locals: { failed_scans: @failed_scans }, layout: false
      else
        render :failed_scans
      end
    rescue => e
      handle_error(e, "failed_scans")
    end

    private

    def require_verified_officer!
      user = current_officer.user

      if user.blank?
        sign_out(current_officer)
        redirect_to new_officer_session_path, alert: "Your officer account is not linked to a citizen profile. Contact support."
      elsif !user.bonid_verified?
        redirect_to new_identity_submission_path(partner: current_officer.partner&.slug), alert: "Please verify your identity before accessing the officer portal."
      end
    end

    def set_counts
      # Total visible reports (unit + rank scoped); drafts are always own reports only
      @incident_count = current_officer.effective_incident_reports.count
      @draft_count    = current_officer.incident_reports.status_draft.count
    end

    def handle_error(exception, action)
      frame_id = "#{action.tr('_', '-')}_frame"
      Rails.logger.error("Error in #{action}: #{exception.message}")
      render turbo_stream: turbo_stream.replace(
        frame_id,
        partial: "shared/error",
        locals: { message: "Something went wrong. Please try again." }
      ), status: :internal_server_error
    end

    def load_hot_zone_data
      # Date range for hot zone data (last 30 days)
      start_date = 30.days.ago.to_date
      end_date = Date.current

      # Scope hot zone data to what this officer may see (unit + rank + JTF override)
      scoped_reports = current_officer.effective_incident_reports
                                      .where(occurred_at: start_date..end_date)

      # Calculate zone data with crime type and severity
      @zone_data = scoped_reports.joins(:address)
                     .where.not(addresses: { commune_id: nil })
                     .includes(:address)
                     .group_by { |r| r.address.commune_id }
                     .map do |commune_id, reports|
        commune = Commune.find_by(id: commune_id)
        next unless commune

        # Crime type breakdown - sort by count descending
        crime_breakdown = reports.group_by(&:crime_type)
                                 .transform_values(&:size)
                                 .sort_by { |_, v| -v }

        # Calculate average severity for the zone
        severities = reports.map { |r| crime_severity_for(r) }.compact
        avg_severity = severities.any? ? (severities.sum.to_f / severities.size).round(1) : nil

        {
          commune_id: commune_id,
          commune_name: commune.name,
          department: commune.department&.name,
          count: reports.size,
          top_crime_type: crime_breakdown.first&.first&.to_s&.humanize,
          top_crime_count: crime_breakdown.first&.last || 0,
          avg_severity: avg_severity,
          severity_label: severity_label(avg_severity)
        }
      end.compact

      # Calculate department breakdown
      @department_breakdown = scoped_reports.joins(:address)
                               .joins("INNER JOIN departments ON addresses.department_id = departments.id")
                               .group("departments.name").count.sort_by { |_, v| -v }
    end

    def crime_severity_for(report)
      # Check for new CrimeType model first
      return report.crime_type_record&.base_severity if report.respond_to?(:crime_type_record) && report.crime_type_record_id.present?
      # Fall back to CrimeConstants lookup
      CrimeConstants::CRIME_SEVERITY[report.crime_type&.to_s&.downcase]
    end

    def severity_label(value)
      return nil unless value
      case value.round
      when 1 then "Low"
      when 2 then "Minor"
      when 3 then "Moderate"
      when 4 then "Serious"
      when 5 then "Critical"
      else nil
      end
    end
  end
end
