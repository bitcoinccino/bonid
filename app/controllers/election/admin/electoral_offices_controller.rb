# frozen_string_literal: true

# Read-only oversight of CEP's BED/BEK roster from the Command Center.
#
# Per the AdminUser-vs-CEP boundary (saved in memory), AdminUsers monitor
# activity and security; CEP partner-portal users own all election ops
# including BED/BEK CRUD. This controller used to mirror the partner-portal
# CRUD; that surface was deleted because it duplicated work CEP owns and
# created auth-boundary collisions for partner users who clicked through.
#
# Citizens read from the same `ElectoralOffice` table via the public
# locator; partner-portal admins own writes.
module Election
  module Admin
    class ElectoralOfficesController < ::Admin::BaseController
      include Election::Admin::CepAdminGate

      # GET /admin/electoral_offices
      def index
        @office_type_filter = ElectoralOffice::OFFICE_TYPES.include?(params[:office_type]) ? params[:office_type] : nil
        @status_filter      = ElectoralOffice::STATUSES.include?(params[:status]) ? params[:status] : nil

        scope = ElectoralOffice.includes(:address, :department, :commune).ordered
        scope = scope.where(office_type: @office_type_filter) if @office_type_filter
        scope = scope.where(status: @status_filter) if @status_filter
        scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?

        @offices = scope
        @counts = {
          total:   ElectoralOffice.count,
          bed:     ElectoralOffice.bed.count,
          bek:     ElectoralOffice.bek.count,
          open:    ElectoralOffice.open.count,
          planned: ElectoralOffice.planned.count
        }
      end
    end
  end
end
