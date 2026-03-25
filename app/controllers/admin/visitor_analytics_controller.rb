# frozen_string_literal: true

module Admin
  class VisitorAnalyticsController < Admin::ApplicationController
    def index
      scope = VisitorSubmission.all
      scope = apply_date_filter(scope)

      # Geography & demographics
      @by_department    = VisitorSubmission.analytics_by_department(scope)
      @by_accommodation = VisitorSubmission.analytics_by_accommodation(scope)
      @by_entry_mode    = VisitorSubmission.analytics_by_entry_mode(scope)
      @by_nationality   = VisitorSubmission.analytics_by_nationality(scope)
      @by_gender        = VisitorSubmission.analytics_by_gender(scope)
      @by_age_group     = VisitorSubmission.analytics_by_age_group(scope)
      @by_season        = VisitorSubmission.analytics_by_season(scope)

      # Transport + time
      @by_airline = scope.group(:transport_provider).count
      @by_month   = scope.group_by_month(:created_at).count

      respond_to do |format|
        format.html
        format.csv do
          send_data VisitorSubmission.to_csv(scope),
            filename: "visitor-analytics-#{Date.today}.csv"
        end
      end
    end

    private

    def apply_date_filter(scope)
      return scope if params[:from].blank? || params[:to].blank?

      scope.where(created_at: params[:from]..params[:to])
    end
  end
end
