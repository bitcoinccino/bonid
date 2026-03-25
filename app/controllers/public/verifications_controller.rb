# frozen_string_literal: true

module Public
  class VerificationsController < ApplicationController
    layout "public"

    skip_before_action :authenticate_user!, raise: false
    skip_before_action :enforce_namespace_access, raise: false

    def show
      token        = params[:verification_token] || params[:token]
      partner_slug = params[:partner]

      # --- Step 1: Locate submission
      @submission = IdentitySubmission.approved.find_by(verification_token: token)
      unless @submission
        render "public/verification_error", status: :not_found and return
      end

      # --- Step 2: Expiry check
      if @submission.expires_at&.past?
        render "public/verification_expired", status: :gone and return
      end

      # --- Step 3: Partner (optional)
      @partner = Partner.find_by(slug: partner_slug)

      # --- Step 4: Log scan (NON-BLOCKING)
      QrScanLogger.log!(
        submission: @submission,
        request: request,
        source: "public_scan",
        partner: @partner
      )

      # --- Step 5: Render certificate (no redirect)
      render "identity_submissions/verified_profile"
    end
  end
end
