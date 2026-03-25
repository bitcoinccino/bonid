# app/controllers/reviewers/application_controller.rb
module Reviewers
  class ApplicationController < ApplicationController
    layout "reviewer"
    before_action :authenticate_reviewer!

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
  end
end
