# frozen_string_literal: true

module PartnerPortal
  module LawEnforcement
    class SearchController < PartnerPortal::LawEnforcement::BaseController
      # GET /partner_portal/law_enforcement/search?q=...
      # Returns JSON results grouped by type: officers, reports, citizens
      def index
        query = params[:q].to_s.strip
        return render json: { results: { officers: [], reports: [], citizens: [] } } if query.length < 2

        sanitized = ActiveRecord::Base.sanitize_sql_like(query)

        render json: {
          results: {
            officers: search_officers(sanitized).map { |o| serialize_officer(o) },
            reports:  search_reports(sanitized).map  { |r| serialize_report(r) },
            citizens: search_citizens(sanitized).map { |c| serialize_citizen(c) }
          }
        }
      end

      private

      def search_officers(q)
        apply_portal_officer_scope(@current_partner.officers)
          .where(
            "officers.first_name ILIKE :q OR officers.last_name ILIKE :q " \
            "OR officers.badge_id ILIKE :q " \
            "OR (officers.first_name || ' ' || officers.last_name) ILIKE :q",
            q: "%#{q}%"
          )
          .limit(5)
      end

      def search_reports(q)
        apply_portal_incident_scope(@current_partner.incident_reports)
          .where(
            "incident_reports.report_id ILIKE :q OR incident_reports.crime_type ILIKE :q",
            q: "%#{q}%"
          )
          .limit(5)
      end

      def search_citizens(q)
        @current_partner.identity_submissions
          .approved
          .joins(:user)
          .where(
            "identity_submissions.bonid ILIKE :q " \
            "OR users.first_name ILIKE :q OR users.last_name ILIKE :q " \
            "OR (users.first_name || ' ' || users.last_name) ILIKE :q",
            q: "%#{q}%"
          )
          .includes(:user)
          .limit(5)
      end

      def serialize_officer(officer)
        {
          name:     officer.full_name,
          badge_id: officer.badge_id,
          rank:     officer.rank&.titleize,
          unit:     officer.unit_name,
          status:   officer.status,
          url:      partner_portal_law_enforcement_officer_path(officer)
        }
      end

      def serialize_report(report)
        {
          report_id:  report.report_id,
          crime_type: report.crime_type&.humanize,
          status:     report.status&.titleize,
          date:       report.created_at&.strftime("%b %d, %Y"),
          url:        partner_portal_law_enforcement_incident_report_path(report)
        }
      end

      def serialize_citizen(submission)
        {
          bonid:  submission.bonid,
          name:   submission.user&.full_name || "Unknown",
          status: submission.status&.titleize
        }
      end
    end
  end
end
