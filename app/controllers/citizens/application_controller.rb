class Citizens::ApplicationController < ApplicationController
  before_action :authenticate_citizen!

  layout :determine_layout

  private

  # ----------------------------------------------------------
  # Select the correct layout based on whether user is logged in
  # ----------------------------------------------------------
  def determine_layout
    if citizen_signed_in?
      "citizen"         # full dashboard layout
    else
      "citizen_auth"   # login/register/forgot-password
    end
  end

  # NOTE: Officers ARE citizens first - they should have full access to their
  # citizen portal to view their BonID, scan history, etc.
  # The officer role is an additional role, not a replacement for citizen access.
end
