# app/controllers/reviewers/sessions_controller.rb
module Reviewers
  class SessionsController < Devise::SessionsController
    layout "reviewer"

    # GET /reviewer/sign_in
    def new
      super
    end

    # POST /reviewer/sign_in
    def create
      super do |user|
        # --- BonID Verification Required ---
        unless user.bonid_verified?
          sign_out user
          redirect_to new_reviewer_session_path,
            alert: "Your BonID must be VERIFIED before accessing the Reviewer Portal." and return
        end

        # --- Must have reviewer role ---
        unless user.has_role?(:reviewer)
          sign_out user
          redirect_to new_reviewer_session_path,
            alert: "You are not authorized as a Reviewer." and return
        end

        # --- Success: reviewer login ---
        redirect_to reviewers_identity_submissions_path,
          notice: "Welcome, reviewer!" and return
      end
    end

    # DELETE /reviewer/sign_out
    def destroy
      super
    end
  end
end
