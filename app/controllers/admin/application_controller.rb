class Admin::ApplicationController < ::ApplicationController
  include Pundit::Authorization
  layout "admin"

  before_action :authenticate_admin_user!
  before_action :ensure_guidelines_confirmed
  before_action :set_fraud_alert_count

  private

  def set_fraud_alert_count
    @fraud_alerts_count = Rails.cache.fetch("admin/fraud_alerts_count", expires_in: 2.minutes) do
      IdentitySubmission
        .where(status: :rejected)
        .where(rejection_reason: "duplicate_identity")
        .where("created_at > ?", 30.days.ago)
        .count
    end
    @unread_notifications_count = @fraud_alerts_count
  end

  def pundit_user
    current_admin_user
  end

  def ensure_guidelines_confirmed
    return unless current_admin_user
    return if session[:admin_guidelines_confirmed]

    if controller_name != "guidelines"
      redirect_to admin_guidelines_path,
                  alert: "Please confirm guidelines before proceeding."
    end
  end
end
