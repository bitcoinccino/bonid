# frozen_string_literal: true

module Admin
  class PartnerAuditLogsController < Admin::ApplicationController
    def index
      @logs = PartnerAuditLog
                .includes(:partner, :admin_user)
                .order(created_at: :desc)
                .limit(500) # ✅ Prevent overly heavy loads
    end

    def show
      @log = PartnerAuditLog.find(params[:id])
    end
  end
end
