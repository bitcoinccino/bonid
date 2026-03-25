module Admin
  class SchemasController < Admin::ApplicationController
    before_action :set_schema, only: [ :show, :edit, :update, :approve, :reject, :deactivate, :destroy ]

    # === LIST ALL SCHEMAS ===
    def index
      @templates = PartnerSchema.admin_templates.order(created_at: :desc)
      @pending   = PartnerSchema.where(active: false, approved_at: nil).order(created_at: :asc)
      @active    = PartnerSchema.where(active: true).order(created_at: :desc)
    end

    # === STEP 1: SELECT SECTOR ===
    def new_sector
      @schema = PartnerSchema.new
      @sectors = Partner::SECTORS.keys
    end

    # === STEP 2: SELECT PARTNER ===
    def select_partners
      @sector = params[:sector]
      @partners = Partner.where(verified: true, sector: @sector).order(:name)
    end

    # === STEP 3: BUILD SCHEMA ===
    def new
      @partner = Partner.find(params[:partner_id])
      @schema = PartnerSchema.new(partner: @partner, sector: @partner.sector)
    end

    def create
      @schema = PartnerSchema.new(schema_params)
      @schema.partner = Partner.find(params[:partner_id]) if params[:partner_id].present?
      @schema.template = false
      @schema.structure ||= {}

      if @schema.save
        redirect_to admin_schemas_path, notice: "Schema created successfully for #{@schema.partner.name}."
      else
        @partner = @schema.partner
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @schema.update(schema_params)
        redirect_to admin_schemas_path, notice: "Schema updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def show; end

    def approve
      @schema.approved!(current_admin_user)
      redirect_to admin_schemas_path, notice: "Schema approved and activated."
    end

    def reject
      @schema.update(active: false, approved_by: nil, approved_at: nil)
      redirect_to admin_schemas_path, alert: "Schema rejected."
    end

    def deactivate
      @schema.deactivated!
      redirect_to admin_schemas_path, alert: "Schema deactivated."
    end

    def destroy
      @schema.destroy
      redirect_to admin_schemas_path, notice: "Schema deleted."
    end

    private

    def set_schema
      @schema = PartnerSchema.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_schemas_path, alert: "Schema not found."
    end

    def schema_params
      params.require(:partner_schema).permit(
        :name, :record_type, :sector, :visibility, :version,
        :partner_id, structure: {}, validation_rules: {}
      )
    end
  end
end
