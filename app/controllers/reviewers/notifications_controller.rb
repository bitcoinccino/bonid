module Reviewers
  class NotificationsController < Reviewers::ApplicationController
    def index
      @notifications = ReviewerNotification.where(reviewer: current_reviewer)
                                           .order(created_at: :desc)
    end
  end
end
