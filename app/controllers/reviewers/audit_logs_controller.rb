# frozen_string_literal: true

module Reviewers
  class AuditLogsController < Reviewers::ApplicationController
    def index
      @activities = ReviewerActivity.for_reviewer(current_reviewer.id)
                                    .includes(:target)
                                    .recent
                                    .page(params[:page]).per(25)
    end
  end
end
