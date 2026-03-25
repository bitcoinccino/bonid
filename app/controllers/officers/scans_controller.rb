# frozen_string_literal: true

module Officers
  class ScansController < Officers::BaseController
    before_action :authenticate_officer!

    def new
      @recent_scans = current_officer.qr_scans
                                     .includes(:identity_submission)
                                     .order(created_at: :desc)
                                     .limit(5)
    end

    def create
      # Handled by BonidLookupsController
      redirect_to officers_bonid_lookups_path
    end

    def create_qrcode
      # Handled by BonidLookupsController
      redirect_to officers_bonid_lookups_path
    end
  end
end
