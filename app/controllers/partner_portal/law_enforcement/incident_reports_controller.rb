module PartnerPortal
  module LawEnforcement
    class IncidentReportsController < PartnerPortal::LawEnforcement::BaseController
      before_action :set_partner
      before_action :set_incident_report, only: [:show, :approve, :reject, :escalate, :request_info]

      def index
        @filter = params[:filter] || "all"

        # Apply unit scope: unit-scoped admins only see their unit's reports
        base = apply_portal_incident_scope(
          @partner.incident_reports.includes(
            :incident_reviews,
            :address,
            person_involvements: [:user, :visitor_submission],
            officer: { user: :identity_submissions }
          )
        )

        case @filter
        when "pending_review"
          @incident_reports = base.joins(:incident_reviews)
                                  .where(incident_reviews: { decision: :pending })
                                  .distinct
        when "overdue"
          @incident_reports = base.joins(:incident_reviews)
                                  .where(incident_reviews: { decision: :pending })
                                  .where("incident_reviews.deadline_at < ?", Time.current)
                                  .distinct
        when "approved"
          @incident_reports = base.where(status: :approved)
        when "rejected"
          @incident_reports = base.where(status: :rejected)
        when "escalated"
          @incident_reports = base.where(status: :escalated)
        else
          @incident_reports = base
        end

        @incident_reports = @incident_reports.order(created_at: :desc)

        # Stats scoped to what this admin can see (unit-scoped or full)
        scoped_base = apply_portal_incident_scope(@partner.incident_reports)
        @stats = {
          total:          scoped_base.count,
          pending_review: scoped_base.joins(:incident_reviews)
                                     .where(incident_reviews: { decision: :pending }).distinct.count,
          overdue:        scoped_base.joins(:incident_reviews)
                                     .where(incident_reviews: { decision: :pending })
                                     .where("incident_reviews.deadline_at < ?", Time.current).distinct.count,
          approved:       scoped_base.where(status: :approved).count,
          rejected:       scoped_base.where(status: :rejected).count
        }
      end

      def show
        @review = @incident_report.current_review
        @person_involvements = @incident_report.person_involvements
                                               .includes(:user, :visitor_submission, :address)
        @officer = @incident_report.officer
        @bonid_submission = @officer&.user&.identity_submissions&.approved&.last
        @address = @incident_report.address
      end

      # Review Actions
      def approve
        return redirect_to_report_with_draft_error if @incident_report.status_draft?

        ActiveRecord::Base.transaction do
          @incident_report.update!(status: :approved)
          @incident_report.current_review&.complete!(
            decision: :approved,
            summary: params[:summary]
          )
        end

        # Notify officer of approval
        notify_officer_of_decision("approved")

        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    notice: "Report approved successfully."
      rescue => e
        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    alert: "Failed to approve report: #{e.message}"
      end

      def reject
        return redirect_to_report_with_draft_error if @incident_report.status_draft?

        if params[:summary].blank?
          redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                      alert: "Rejection reason is required."
          return
        end

        ActiveRecord::Base.transaction do
          @incident_report.update!(status: :rejected)
          @incident_report.current_review&.complete!(
            decision: :rejected,
            summary: params[:summary]
          )
        end

        # Notify officer of rejection with reason
        notify_officer_of_decision("rejected", params[:summary])

        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    notice: "Report rejected. Officer has been notified."
      rescue => e
        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    alert: "Failed to reject report: #{e.message}"
      end

      def escalate
        return redirect_to_report_with_draft_error if @incident_report.status_draft?

        ActiveRecord::Base.transaction do
          @incident_report.update!(status: :escalated)
          @incident_report.current_review&.complete!(
            decision: :escalated,
            summary: params[:summary] || "Escalated to higher authority"
          )
        end

        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    notice: "Report escalated to higher authority."
      rescue => e
        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    alert: "Failed to escalate report: #{e.message}"
      end

      def request_info
        return redirect_to_report_with_draft_error if @incident_report.status_draft?

        ActiveRecord::Base.transaction do
          @incident_report.current_review&.update!(
            decision: :info_requested,
            summary: params[:summary]
          )
        end

        # Notify officer that more information is needed
        notify_officer_of_decision("info_requested", params[:summary])

        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    notice: "Information request sent to officer."
      rescue => e
        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    alert: "Failed to request info: #{e.message}"
      end

      def new
        @incident_report = @partner.incident_reports.build
      end

      def create
        @incident_report = @partner.incident_reports.build(incident_report_params)
        if @incident_report.save
          redirect_to partner_portal_law_enforcement_incident_reports_path,
                      notice: "Incident report created successfully."
        else
          render :new
        end
      end

      private

      def set_partner
        @partner = @current_partner
      end

      def set_incident_report
        # Scope to what this admin may see (unit or full) — prevents UUID enumeration
        # and cross-unit access even when UUIDs are known.
        base = apply_portal_incident_scope(@partner.incident_reports)
        @incident_report = base.find_by!(uuid: params[:id])
      rescue ActiveRecord::RecordNotFound
        redirect_to partner_portal_law_enforcement_incident_reports_path,
                    alert: "Rapport introuvable ou accès refusé."
      end

      def incident_report_params
        params.require(:incident_report).permit(:title, :description, :status)
      end

      def redirect_to_report_with_draft_error
        redirect_to partner_portal_law_enforcement_incident_report_path(@incident_report),
                    alert: "Ce rapport est encore en brouillon. L'agent doit le signer et le soumettre avant qu'il puisse être examiné."
      end

      def notify_officer_of_decision(decision, reason = nil)
        officer = @incident_report.officer
        return unless officer&.email.present?

        # Queue email notification to officer
        # Officers::OfficerMailer.with(
        #   officer: officer,
        #   incident_report: @incident_report,
        #   decision: decision,
        #   reason: reason
        # ).review_decision.deliver_later
      rescue => e
        Rails.logger.error "[IncidentReport] Failed to notify officer: #{e.message}"
      end
    end
  end
end
