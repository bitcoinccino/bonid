module PartnerPortal
  class PartnerSchemasController < PartnerPortal::BaseController
    before_action :set_partner_schema, only: %i[show edit update destroy approve]

    def index
      @schemas = current_partner.partner_schemas.order(created_at: :desc)
    end

    def new
      @schema = current_partner.partner_schemas.new
    end

    def create
      @schema = current_partner.partner_schemas.new(schema_params)
      if @schema.save
        redirect_to partner_portal_partner_schemas_path, notice: "✅ Schema created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show; end
    def edit; end

    def update
      if @schema.update(schema_params)
        redirect_to partner_portal_partner_schema_path(@schema), notice: "✅ Schema updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @schema.destroy
      redirect_to partner_portal_partner_schemas_path, notice: "🗑️ Schema deleted."
    end

    def approve
      @schema.update(approved_at: Time.current, approved_by: current_admin)
      redirect_to partner_portal_partner_schemas_path, notice: "✅ Schema approved."
    end

    private

    def set_partner_schema
      @schema = current_partner.partner_schemas.find(params[:id])
    end

    def schema_params
      params.require(:partner_schema).permit(
        :name, :record_type, :visibility, :active,
        structure: {}, validation_rules: {}
      )
    end
  end
end
