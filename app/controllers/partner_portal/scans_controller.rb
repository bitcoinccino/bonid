# frozen_string_literal: true

module PartnerPortal
  class ScansController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!

    def index
      @partner = @current_partner
      @free_lookups_remaining = @partner.free_portal_lookups_remaining
      @credit_balance = @partner.credit_balance
      @scans = @partner.qr_scans
                  .includes(identity_submission: :user)
                  .order(created_at: :desc)
                  .page(params[:page])
                  .per(20)
    end

    def show
      @scan = @current_partner.qr_scans.find(params[:id])
    end
  end
end
