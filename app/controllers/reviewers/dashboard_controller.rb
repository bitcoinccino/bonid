module Reviewers
  class DashboardController < Reviewers::ApplicationController
    def index
      @total_submissions = IdentitySubmission.count
      @pending = IdentitySubmission.where(status: "pending").count
      @approved = IdentitySubmission.where(status: "approved").count
      @rejected = IdentitySubmission.where(status: "rejected").count

      @recent = IdentitySubmission.order(created_at: :desc).limit(10)
    end
  end
end
