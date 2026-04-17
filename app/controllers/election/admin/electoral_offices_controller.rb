# frozen_string_literal: true

# CRUD for CEP's electoral offices (BED + BEK) — scoped to CEP
# administrators under the Command Center. Each row is a physical CEP
# building; the citizen-side locator reads from the same table.
#
# Addresses use the polymorphic `Address` model already wired into Partners
# and Institutions (see `has_one :address, as: :addressable` in
# ElectoralOffice). The form submits `address_attributes` as nested params;
# ActiveRecord handles the cascade (department → arrondissement → commune →
# section) via the existing Address callbacks.
module Election
  module Admin
    class ElectoralOfficesController < ::Admin::BaseController
      before_action :require_cep_admin!
      before_action :set_office, only: %i[show edit update destroy]

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

      # GET /admin/electoral_offices/new
      def new
        @office = ElectoralOffice.new(status: "planned", priority: 0)
        @office.build_address(country: "Haiti")
      end

      # POST /admin/electoral_offices
      def create
        @office = ElectoralOffice.new(office_params)
        if @office.save
          redirect_to admin_electoral_offices_path,
                      notice: "Biwo elektoral kreye: #{@office.display_label}"
        else
          @office.build_address(country: "Haiti") unless @office.address
          render :new, status: :unprocessable_entity
        end
      end

      # GET /admin/electoral_offices/:id/edit
      def edit
        @office.build_address(country: "Haiti") unless @office.address
      end

      # PATCH /admin/electoral_offices/:id
      def update
        if @office.update(office_params)
          redirect_to admin_electoral_offices_path,
                      notice: "Biwo elektoral mete ajou: #{@office.display_label}"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # DELETE /admin/electoral_offices/:id
      def destroy
        if @office.voter_eligibility_records.any?
          redirect_to admin_electoral_offices_path,
                      alert: "Pa ka efase — biwo sa gen enskripsyon elektè ki lye avè l."
        else
          @office.destroy
          redirect_to admin_electoral_offices_path,
                      notice: "Biwo elektoral efase."
        end
      end

      private

      # Matches Election::Admin::ElectionsController — CEP admin gate. Today
      # this is a logged-in-admin check; a proper CEP role predicate should
      # land in a shared concern (`Election::Admin::CepAdminGate`) next.
      def require_cep_admin!
        return if current_admin_user.present?

        redirect_to admin_login_path,
                    alert: "Aksè refize. Sèlman administratè CEP ka jere biwo BED/BEK."
      end

      def set_office
        @office = ElectoralOffice.includes(:address).find(params[:id])
      end

      def office_params
        params.require(:electoral_office).permit(
          :name, :office_type, :status, :phone, :hours_note, :priority, :notes,
          :department_id, :commune_id,
          address_attributes: %i[
            id street_address locality
            department_id arrondissement_id commune_id communal_section_id
            country postal_code latitude longitude
          ]
        )
      end
    end
  end
end
