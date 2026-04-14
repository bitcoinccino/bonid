# frozen_string_literal: true

module Reviewers
  class IdentitySubmissionsController < Reviewers::ApplicationController
    before_action :authenticate_reviewer!
    before_action :load_admin_controller
    before_action :set_submission, only: %i[
      show update approve reject
      approve_bin reject_bin approve_reset reject_reset
      regenerate_qr verify_signature
    ]

    # ---------------------------------------------------------------------------
    # INDEX
    # ---------------------------------------------------------------------------
    def index
      @submissions = IdentitySubmission.includes(:user)

      # Status filter (pending, approved, rejected, revoked)
      @submissions = @submissions.where(status: params[:status]) if params[:status].present?

      # Fraud alert filter (duplicate_identity rejections)
      if params[:rejection_reason].present?
        @submissions = @submissions.where(status: :rejected, rejection_reason: params[:rejection_reason])
      end

      @submissions = @submissions.order(created_at: :desc)
                                 .page(params[:page]).per(20)

      render "reviewers/identity_submissions/index"
    end

    # ---------------------------------------------------------------------------
    # SHOW — logs "view_submission" for review timer
    # ---------------------------------------------------------------------------
    def show
      ReviewerActivity.log!(
        user:       current_reviewer,
        action:     "view_submission",
        target:     @submission,
        ip_address: request.remote_ip
      )
      render "reviewers/identity_submissions/show"
    end

    # ---------------------------------------------------------------------------
    # FULL ADMIN ACTION DELEGATION (with audit trail)
    # ---------------------------------------------------------------------------
    def update          = forward(:update)
    def approve         = forward_with_audit(:approve)
    def reject          = forward_with_audit(:reject)
    def approve_bin     = forward_with_audit(:approve_bin, audit_action: "approve")
    def reject_bin      = forward_with_audit(:reject_bin,  audit_action: "reject")
    def approve_reset   = forward_with_audit(:approve_reset, audit_action: "approve")
    def reject_reset    = forward_with_audit(:reject_reset,  audit_action: "reject")
    def regenerate_qr   = forward(:regenerate_qr)
    def verify_signature = forward(:verify_signature)
    def bulk_update     = forward(:bulk_update)
    def fallback_lookup = forward(:fallback_lookup)

    private

    def forward(action_name)
      @admin_controller.params   = params
      @admin_controller.request  = request
      @admin_controller.response = response
      @admin_controller.instance_variable_set(:@submission, @submission)

      @admin_controller.send(action_name)
    end

    def forward_with_audit(action_name, audit_action: nil)
      audit_action ||= action_name.to_s
      status_before = @submission&.status

      # Calculate review duration (time since they viewed this submission)
      review_duration = ReviewerActivity.review_duration_for(current_reviewer.id, @submission) if @submission

      # Check for fraud warnings being overridden
      has_fraud_warning = @submission&.metadata&.dig("face_dedup", "duplicate") == true
      overriding = has_fraud_warning && audit_action == "approve"

      forward(action_name)

      # Log the decision after the action completes
      @submission&.reload
      status_changed = @submission && @submission.status != status_before

      if status_changed
        metadata = {
          status_before:   status_before,
          status_after:    @submission.status,
          review_duration: review_duration
        }

        if audit_action == "reject"
          metadata[:rejection_reason] = @submission.rejection_reason
          metadata[:other_reason]     = @submission.other_reason
        end

        ReviewerActivity.log!(
          user:       current_reviewer,
          action:     audit_action,
          target:     @submission,
          ip_address: request.remote_ip,
          metadata:   metadata
        )

        # Log override separately if they approved despite a fraud warning
        if overriding
          ReviewerActivity.log!(
            user:       current_reviewer,
            action:     "override_warning",
            target:     @submission,
            ip_address: request.remote_ip,
            metadata:   {
              warning_type:    "duplicate_identity",
              matched_user_id: @submission.metadata&.dig("face_dedup", "matched_user_id"),
              similarity:      @submission.metadata&.dig("face_dedup", "similarity")
            }
          )
        end
      end
    end

    def load_admin_controller
      @admin_controller = Admin::IdentitySubmissionsController.new
    end

    def set_submission
      @submission = IdentitySubmission.find(params[:id])
    end
  end
end
