module Reviewers
  class AuditLogsController < Reviewers::ApplicationController
    def index
      @logs = PartnerAuditLog.where(admin_user_id: current_reviewer.id)
                             .order(created_at: :desc)
                             .page(params[:page]).per(20)
    end
  end
end
