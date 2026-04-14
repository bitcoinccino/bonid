# frozen_string_literal: true

module PartnerPortal
  class PartnerAuditLogsController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!

    # GET /partner_portal/partner_audit_logs
    def index
      @logs = @current_partner.partner_audit_logs
                .order(created_at: :desc)

      # Filter by event type
      if params[:event].present?
        @logs = @logs.where(event: params[:event])
      end

      # Filter by date range
      if params[:from].present?
        @logs = @logs.where("created_at >= ?", Date.parse(params[:from]).beginning_of_day)
      end
      if params[:to].present?
        @logs = @logs.where("created_at <= ?", Date.parse(params[:to]).end_of_day)
      end

      # Search by details content
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        @logs = @logs.where("details ILIKE ?", search_term)
      end

      # Event type counts for filter badges
      @event_counts = @current_partner.partner_audit_logs
                        .group(:event)
                        .count

      @mismatch_count = @event_counts["identity_mismatch"] || 0

      @logs = @logs.page(params[:page]).per(25)
    end

    # GET /partner_portal/partner_audit_logs/:id
    def show
      @log = @current_partner.partner_audit_logs.find(params[:id])
    end
  end
end
