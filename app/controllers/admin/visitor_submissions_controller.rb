# frozen_string_literal: true

module Admin
  class VisitorSubmissionsController < Admin::ApplicationController
    include BontourisPausable # v1 launch: paused unless BONTOURIS_ENABLED=true
    pause_bontouris_unless_enabled

    before_action :set_visitor_submission, only: [ :show, :approve, :reject, :resend_certificate ]

    def index
      @visitor_submissions =
        VisitorSubmission.order(created_at: :desc).limit(100)
    end

    def show
    end

    def approve
      @visitor_submission.approve!(admin: current_admin_user)

      redirect_to admin_visitor_submission_path(@visitor_submission),
                  notice: "Visitor application approved and BonTouris ID issued."
    rescue => e
      Rails.logger.error(e)
      redirect_back fallback_location: admin_visitor_submission_path(@visitor_submission),
                    alert: "Approval failed."
    end

    def reject
        reason = params.dig(:visitor_submission, :rejection_reason)
        notes  = params.dig(:visitor_submission, :rejection_notes)

        @visitor_submission.reject!(
          admin: current_admin_user,
          reason: reason,
          notes: notes
        )

        redirect_to admin_visitor_submission_path(@visitor_submission),
                    notice: "Visitor application rejected."
      rescue => e
        Rails.logger.error(e)
        redirect_back fallback_location: admin_visitor_submission_path(@visitor_submission),
                      alert: e.message
      end

    # 🔁 NEW: resend certificate (NO state change)
    def resend_certificate
      @visitor_submission.resend_certificate!

      redirect_to admin_visitor_submission_path(@visitor_submission),
                  notice: "BonTouris ID certificate resent successfully."
    rescue => e
      Rails.logger.error(e)
      redirect_back fallback_location: admin_visitor_submission_path(@visitor_submission),
                    alert: "Resend failed."
    end

    private

    def set_visitor_submission
      @visitor_submission = VisitorSubmission.find(params[:id])
    end
  end
end
