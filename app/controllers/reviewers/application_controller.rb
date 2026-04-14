# app/controllers/reviewers/application_controller.rb
module Reviewers
  class ApplicationController < ApplicationController
    layout "reviewer"
    before_action :authenticate_reviewer!
    before_action :set_fraud_alert_count
    before_action :track_last_seen

    # --------------------------------------------------------
    # AUTH CHECK — Must have reviewer role + VERIFIED BonID
    # --------------------------------------------------------
    def authenticate_reviewer!
      unless current_user&.has_role?(:reviewer) && current_user&.bonid_verified?
        redirect_to new_reviewer_session_path,
          alert: "You must have a VERIFIED BonID to continue."
      end
    end

    # --------------------------------------------------------
    # CURRENT REVIEWER HELPER
    # --------------------------------------------------------
    def current_reviewer
      return nil unless current_user&.has_role?(:reviewer)
      return nil unless current_user&.bonid_verified?

      current_user
    end
    helper_method :current_reviewer

    def set_fraud_alert_count
      @fraud_alerts_count = Rails.cache.fetch("admin/fraud_alerts_count", expires_in: 2.minutes) do
        IdentitySubmission
          .where(status: :rejected)
          .where(rejection_reason: "duplicate_identity")
          .where("created_at > ?", 30.days.ago)
          .count
      end
    end

    # --------------------------------------------------------
    # TRACK LAST SEEN — Updates every 5 minutes max (avoids DB spam)
    # --------------------------------------------------------
    def track_last_seen
      return unless current_reviewer

      if current_reviewer.last_seen_at.nil? || current_reviewer.last_seen_at < 5.minutes.ago
        current_reviewer.update_column(:last_seen_at, Time.current)
      end
    end
  end
end
