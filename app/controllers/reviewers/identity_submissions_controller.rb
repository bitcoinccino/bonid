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
                                       .order(created_at: :desc)
                                       .page(params[:page]).per(20)

      render "reviewers/identity_submissions/index"
    end

    # ---------------------------------------------------------------------------
    # SHOW
    # ---------------------------------------------------------------------------
    def show
      render "reviewers/identity_submissions/show"
    end

    # ---------------------------------------------------------------------------
    # FULL ADMIN ACTION DELEGATION
    # ---------------------------------------------------------------------------
    def update          = forward(:update)
    def approve         = forward(:approve)
    def reject          = forward(:reject)
    def approve_bin     = forward(:approve_bin)
    def reject_bin      = forward(:reject_bin)
    def approve_reset   = forward(:approve_reset)
    def reject_reset    = forward(:reject_reset)
    def regenerate_qr   = forward(:regenerate_qr)
    def verify_signature = forward(:verify_signature)
    def bulk_update     = forward(:bulk_update)
    def fallback_lookup = forward(:fallback_lookup)

    private

    def forward(action_name)
      # Pass Rails request stack into admin controller context
      @admin_controller.params   = params
      @admin_controller.request  = request
      @admin_controller.response = response

      # Supply already-fetched submission
      @admin_controller.instance_variable_set(:@submission, @submission)

      @admin_controller.send(action_name)
    end

    def load_admin_controller
      @admin_controller = Admin::IdentitySubmissionsController.new
    end

    def set_submission
      @submission = IdentitySubmission.find(params[:id])
    end
  end
end
