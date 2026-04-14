module Reviewers
  class DashboardController < Reviewers::ApplicationController
    def index
      @total_submissions = IdentitySubmission.count
      @pending = IdentitySubmission.where(status: "pending").count
      @approved = IdentitySubmission.where(status: "approved").count
      @rejected = IdentitySubmission.where(status: "rejected").count

      @recent = IdentitySubmission.order(created_at: :desc).limit(10)

      @recent_fraud_alerts = IdentitySubmission
        .where(status: :rejected, rejection_reason: "duplicate_identity")
        .includes(:user)
        .order(created_at: :desc)
        .limit(5)
    end
  end
end
