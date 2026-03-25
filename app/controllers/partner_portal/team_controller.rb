# frozen_string_literal: true

module PartnerPortal
  class TeamController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!

    def index
      @partner = @current_partner
      @team_members = @partner.users.with_any_role(:partner_admin)
    end
  end
end
