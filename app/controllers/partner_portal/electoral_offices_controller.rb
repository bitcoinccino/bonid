# frozen_string_literal: true

module PartnerPortal
  # Partner-portal CRUD for ElectoralOffice (BED / BEK) — CEP's permanent
  # field offices. CEP partner_admins (User-side role) need to register and
  # maintain BEDs/BEKs themselves so they can assign Ajan Enskripsyon to a
  # specific BEK during team invites without bouncing into the AdminUser-gated
  # Command Center surface (/admin/electoral_offices).
  #
  # The same model + nested Address are reused by the AdminUser-side
  # Election::Admin::ElectoralOfficesController; this controller is the
  # User-side mirror, scoped to the CEP sector.
  class ElectoralOfficesController < PartnerPortal::BaseController
    before_action :ensure_cep_sector!
    before_action :require_partner_admin!, only: %i[new create edit update destroy]
    before_action :set_office,              only: %i[edit update destroy]
    before_action :load_departments,        only: %i[new create edit update]

    # GET /partner_portal/electoral_offices
    def index
      @office_type_filter = ElectoralOffice::OFFICE_TYPES.include?(params[:office_type]) ? params[:office_type] : nil
      @status_filter      = ElectoralOffice::STATUSES.include?(params[:status]) ? params[:status] : nil

      scope = ElectoralOffice.includes(:address, :department, :commune).ordered
      scope = scope.where(office_type: @office_type_filter) if @office_type_filter
      scope = scope.where(status: @status_filter)           if @status_filter
      scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?

      @offices = scope
      @counts = {
        total:    ElectoralOffice.count,
        bed:      ElectoralOffice.bed.count,
        bek:      ElectoralOffice.bek.count,
        open:     ElectoralOffice.open.count,
        planned:  ElectoralOffice.planned.count
      }
    end

    # GET /partner_portal/electoral_offices/new
    def new
      @office = ElectoralOffice.new(status: "planned", priority: 0)
      @office.build_address(country: "Haiti")
    end

    # POST /partner_portal/electoral_offices
    def create
      @office = ElectoralOffice.new(office_params)
      if @office.save
        redirect_to partner_portal_electoral_offices_path,
                    notice: "Biwo elektoral kreye: #{@office.display_label}"
      else
        @office.build_address(country: "Haiti") unless @office.address
        render :new, status: :unprocessable_entity
      end
    end

    # GET /partner_portal/electoral_offices/:id/edit
    def edit
      @office.build_address(country: "Haiti") unless @office.address
    end

    # PATCH /partner_portal/electoral_offices/:id
    def update
      if @office.update(office_params)
        redirect_to partner_portal_electoral_offices_path,
                    notice: "Biwo elektoral mete ajou: #{@office.display_label}"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /partner_portal/electoral_offices/:id
    def destroy
      if @office.voter_eligibility_records.any?
        redirect_to partner_portal_electoral_offices_path,
                    alert: "Pa ka efase — biwo sa gen enskripsyon elektè ki lye avè l."
      else
        @office.destroy
        redirect_to partner_portal_electoral_offices_path,
                    notice: "Biwo elektoral efase."
      end
    end

    private

    def set_office
      @office = ElectoralOffice.includes(:address).find(params[:id])
    end

    # Required by the shared `address` Stimulus cascade — the controller reads
    # the slug map off the department <select> at connect time.
    def load_departments
      @departments = Department.order(:name)
    end

    # `department_id` / `commune_id` are intentionally not permitted — they're
    # derived from the nested address by ElectoralOffice#sync_scope_from_address.
    # `priority` is also dropped from the create/edit form (defaults to 0); if
    # the rare need to pin an office to the top of a list comes back, expose it
    # as a separate "promote" action, not a field on every create form.
    # `hours_note` (free-text) was replaced by structured `operating_hours`.
    def office_params
      base = params.require(:electoral_office).permit(
        :name, :office_type, :status, :phone, :notes,
        address_attributes: %i[
          id street_address locality
          department_id arrondissement_id commune_id communal_section_id
          country postal_code latitude longitude
        ]
      )
      base[:operating_hours] = sanitize_operating_hours(params.dig(:electoral_office, :operating_hours))
      base
    end

    # Strong-params can't express `{day => {idx => {open, close}}}` with
    # arbitrary numeric keys cleanly, so we whitelist by hand: only known day
    # keys, only `open`/`close` strings per slot, drop everything else. The
    # model's normalize_operating_hours then collapses to a clean Array.
    def sanitize_operating_hours(raw)
      return {} if raw.blank?
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      ElectoralOffice::DAYS.each_with_object({}) do |day, acc|
        day_hash = raw[day] || raw[day.to_sym]
        next if day_hash.blank?
        slots = Array(day_hash.respond_to?(:values) ? day_hash.values : day_hash)
        acc[day] = slots.map { |s| { "open" => s["open"].to_s, "close" => s["close"].to_s } }
      end
    end

    # CEP-only surface. Other sectors have no BED/BEK concept; bounce them.
    def ensure_cep_sector!
      sector = (@current_partner.department_sector || @current_partner.sector).to_s.downcase
      return if sector == "cep"
      redirect_to partner_portal_dashboard_path,
                  alert: "Aksè refize. Sèlman patnè CEP ka jere biwo elektoral."
    end

    # Mirrors PartnerPortal::TeamController#require_admin! — only partner_admins
    # may create/edit/destroy BED/BEK records. Read-only index is open to all
    # CEP staff so they can see what offices exist.
    def require_partner_admin!
      return if current_portal_user&.has_role?(:partner_admin)
      redirect_to partner_portal_dashboard_path,
                  alert: "Sèlman administratè ka jere biwo elektoral."
    end
  end
end
