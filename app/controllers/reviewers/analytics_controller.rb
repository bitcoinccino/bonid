module Reviewers
  class AnalyticsController < Reviewers::ApplicationController
    def index
      @daily = IdentitySubmission.group_by_day(:created_at).count
      @approval_rate =
        IdentitySubmission.where(status: "approved").count.to_f /
        IdentitySubmission.count.to_f * 100 rescue 0
    end
  end
end
