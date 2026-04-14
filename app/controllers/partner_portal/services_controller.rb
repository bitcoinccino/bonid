# frozen_string_literal: true

module PartnerPortal
  class ServicesController < PartnerPortal::BaseController
    before_action :set_service, only: %i[edit update destroy toggle publish version_history]
    before_action :enable_immersive_form, only: %i[new create edit]

    # ==============================================================
    # ACTIONS
    # ==============================================================

    def index
      @services = @current_partner.partner_schemas
                                   .where(citizen_facing: true)
                                   .order(position: :asc, created_at: :desc)
    end

    def new
      @service = @current_partner.partner_schemas.new(
        citizen_facing: true,
        visibility: "public",
        sector: @current_partner.sector,
        pricing_type: "free",
        currency: "HTG",
        service_category: "application",
        service_icon: "ri-file-text-line",
        structure: { "fields" => [] }
      )

      @templates = load_templates
    end

    def create
      @service = @current_partner.partner_schemas.new(service_params)
      @service.citizen_facing = true
      @service.visibility = "public"
      @service.sector = @current_partner.sector
      @service.version = 1
      @service.record_type = @service.record_type.presence || "service"
      @service.form_revision = Time.current.strftime("%Y-%m")
      @service.structure = parse_structure_json

      if @service.save
        redirect_to partner_portal_services_path, notice: "Sèvis kreye avèk siksè. Ap tann apwobasyon admin."
      else
        @templates = load_templates
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @templates = load_templates

      # Handle rollback request (loads old version structure into draft)
      if params[:rollback_to].present?
        @service.rollback_to!(params[:rollback_to].to_i)
        flash.now[:notice] = "Vèsyon #{params[:rollback_to]} chaje kòm bouyon. Modifye epi pibliye."
      end

      # Handle discard draft request
      if params[:discard_draft].present?
        @service.discard_draft!
        redirect_to edit_partner_portal_service_path(@service), notice: "Bouyon efase. Retounen nan vèsyon pibliye a."
        return
      end

      # If the service is published and has draft changes, load draft_structure
      # into the form builder so the partner continues editing the draft
      @editing_structure = @service.working_structure
      @is_published = @service.published?
      @has_draft = @service.has_draft_changes?
    end

    def update
      @service.assign_attributes(service_params)
      @service.form_revision = Time.current.strftime("%Y-%m")
      new_structure = parse_structure_json

      if @service.published?
        # Published services save edits to draft_structure (non-destructive)
        @service.draft_structure = new_structure
      else
        # Draft services write directly to structure
        @service.structure = new_structure
      end

      if @service.save
        notice = @service.published? ? "Bouyon sove. Pibliye lè ou pare." : "Sèvis mete ajou."
        redirect_to partner_portal_services_path, notice: notice
      else
        @templates = load_templates
        @editing_structure = new_structure
        @is_published = @service.published?
        @has_draft = @service.has_draft_changes?
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @service.destroy
      redirect_to partner_portal_services_path, notice: "Sèvis retire."
    end

    def toggle
      @service.update!(active: !@service.active?)
      status = @service.active? ? "aktive" : "dezaktive"
      redirect_to partner_portal_services_path, notice: "Sèvis #{status}."
    end

    def publish
      @service.publish!
      redirect_to partner_portal_services_path, notice: "Sèvis pibliye! Vèsyon #{@service.version} aktif kounye a."
    rescue => e
      redirect_to edit_partner_portal_service_path(@service), alert: "Erè: #{e.message}"
    end

    def version_history
      @versions = @service.version_history
    end

    # GET /partner_portal/services/templates — returns template JSON for JS
    def templates
      render json: load_templates
    end

    private

    def set_service
      @service = @current_partner.partner_schemas.where(citizen_facing: true).find(params[:id])
    end

    def enable_immersive_form
      @immersive_form = true
    end

    def service_params
      permitted = params.require(:partner_schema).permit(
        :name, :record_type, :description,
        :form_code,
        :pricing_type, :price_cents, :currency,
        :service_icon, :service_category, :position,
        :requires_signature, :auto_stamp,
        :capacity, :cover_image,
        :starts_at, :ends_at
      )

      # Partner enters price in HTG/USD (e.g. 500.00), convert to centimes for storage
      if permitted[:price_cents].present?
        permitted[:price_cents] = (permitted[:price_cents].to_f * 100).round
      end

      # Auto-correct pricing_type if price was set but type is still "free"
      if permitted[:price_cents].to_i > 0 && permitted[:pricing_type] == "free"
        permitted[:pricing_type] = "fixed"
      elsif permitted[:price_cents].to_i.zero? && permitted[:pricing_type] != "variable"
        permitted[:pricing_type] = "free"
      end

      permitted
    end

    # The Stimulus controller serializes the visual builder fields into
    # a hidden input as JSON. We parse it here.
    def parse_structure_json
      raw = params.dig(:partner_schema, :structure_json).to_s
      parsed = raw.present? ? JSON.parse(raw) : { "fields" => [] }
      return { "fields" => [] } unless parsed.is_a?(Hash)

      # Ensure fields array exists
      parsed["fields"] = [] unless parsed["fields"].is_a?(Array)

      # Keep steps if present
      parsed["steps"] = [] unless parsed["steps"].is_a?(Array)
      parsed.delete("steps") if parsed["steps"].empty?

      parsed
    rescue JSON::ParserError
      { "fields" => [] }
    end

    # ── Database-driven templates ──
    # Returns templates from the database instead of hardcoded constants.
    # Sources (in priority order):
    #   1. Partner's own saved templates (partner_id = current partner)
    #   2. Admin templates for this sector (partner_id = nil, sector = partner's sector)
    #   3. Global admin templates (partner_id = nil, sector = nil or matches)
    def load_templates
      templates = PartnerSchema
        .where(template: true)
        .where(
          "(partner_id = :pid) OR (partner_id IS NULL AND (sector = :sector OR sector IS NULL))",
          pid: @current_partner.id,
          sector: @current_partner.sector
        )
        .order(:name)

      templates.map do |t|
        {
          id: t.id,
          name: t.name,
          icon: t.service_icon || "ri-file-text-line",
          fields: t.fields,
          record_type: t.record_type,
          category: t.service_category,
          pricing: t.pricing_type,
          own: t.partner_id == @current_partner.id
        }
      end
    end
  end
end
