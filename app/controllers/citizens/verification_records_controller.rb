# app/controllers/citizens/verification_records_controller.rb
module Citizens
  class VerificationRecordsController < ApplicationController
    include RecordSchemas::DefaultTemplates

    before_action :authenticate_citizen!
    before_action :set_record, only: %i[show edit update destroy]
    before_action :set_defaults, only: [ :create ]
    before_action :load_departments, only: [ :new, :edit ]

    layout "citizen"

    # === Index ===
    def index
      scope = current_citizen.verification_records.order(created_at: :desc)
      scope = scope.for_type(params[:record_type]) if params[:record_type].present?
      scope = scope.where(access_level: params[:visibility]) if params[:visibility].present?
      scope = scope.where(category: params[:category]) if params[:category].present?
      @records = scope.page(params[:page]).per(5)
    end

    # === Show ===
    def show
      record_type = @record.record_type
      details_partial = "citizens/verification_records/#{record_type}/#{record_type}_details"

      if lookup_context.exists?(details_partial, [], true)
        render partial: details_partial, locals: { record: @record }, layout: false
      else
        render partial: "citizens/verification_records/shared/select_type", layout: false
      end
    end

    # === New ===
    def new
      type     = params[:record_type].to_s.downcase.presence
      category = params[:category].to_s.downcase.presence

      # Step 1: show type selector if none chosen
      unless type.present?
        @available_types = {
          "Education" => "education",
          "Business"  => "business",
          "Property"  => "property",
          "Health"    => "health",
          "Bank"      => "bank"
        }

        render partial: "citizens/verification_records/shared/select_type",
               locals: { available_types: @available_types },
               layout: false and return
      end

      # Step 2: default category by type
      category ||= case type
      when "property"  then "land_transaction"
      when "business"  then "registration"
      when "health"    then "patient_record"
      when "education" then "academic_record"
      when "bank"      then "financial_record"
      else "base"
      end

      # Step 3: initialize new record
      @record = current_citizen.verification_records.new(
        record_type:   type,
        category:      category,
        access_level:  :private_access,
        status:        "pending",
        source:        "citizen_portal",
        data:          default_template_for(type)
      )

      # === CRITICAL FIX: Build and link address correctly ===
      address = @record.build_address
      address.addressable = @record

      # === Prefill from citizen's address if property and exists ===
      if type == "property" && current_citizen.address.present?
        prefill_attrs = current_citizen.address.attributes.slice(
          "street_address", "locality", "postal_code", "country",
          "department_id", "arrondissement_id", "commune_id", "communal_section_id"
        )
        address.assign_attributes(prefill_attrs)
      end

      # Step 4: render correct form
      form_partial = "citizens/verification_records/#{type}/#{type}_form"
      if lookup_context.exists?(form_partial, [], true)
        render partial: form_partial, locals: { record: @record }, layout: false
      else
        render partial: "citizens/verification_records/form", locals: { record: @record }, layout: false
      end
    end

    # === Create ===
    def create
      @record = current_citizen.verification_records.new(verification_record_params)
      @record.record_type ||= params[:record_type]
      @record.status ||= "pending"

      if @record.save
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append(
              "verification_records_table",
              partial: "citizens/verification_records/shared/table_row",
              locals: { record: @record }
            )
          end
          format.html { redirect_to citizens_verification_records_path, notice: "Record created successfully." }
        end
      else
        respond_to do |format|
          format.turbo_stream { render :new, status: :unprocessable_entity }
          format.html { render :new, status: :unprocessable_entity }
        end
      end
    end

    # === Edit ===
    def edit
      @record.record_type ||= params[:record_type] || @record.data["record_type"]
      @record.category    ||= params[:category] || @record.data["category"]

      type = @record.record_type
      form_partial = "citizens/verification_records/#{type}/#{type}_form"

      if lookup_context.exists?(form_partial, [], true)
        render partial: form_partial, locals: { record: @record }, layout: false
      else
        render partial: "citizens/verification_records/form", locals: { record: @record }, layout: false
      end
    end

    # === Update ===
    def update
      if @record.update(verification_record_params)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to citizens_verification_records_path, notice: "Record updated successfully." }
        end
      else
        respond_to do |format|
          format.turbo_stream { render :edit, status: :unprocessable_entity }
          format.html { render :edit, status: :unprocessable_entity }
        end
      end
    end

    # === Destroy ===
    def destroy
      @record.destroy
      respond_to do |format|
        format.html { redirect_to citizens_verification_records_path, notice: "Record deleted successfully." }
        format.turbo_stream
      end
    end

    private

    def load_departments
      @departments = Department.all.order(:name)
    end

    # === Strong Params ===
    def verification_record_params
      base = params.require(:verification_record)
                   .permit(
                     :record_type, :category, :status, :source, :access_level,
                     data: {},
                     address_attributes: [
                       :id, :street_address, :locality, :postal_code, :country,
                       :department_id, :arrondissement_id, :commune_id,
                       :communal_section_id, :_destroy
                     ]
                   )

      record_hash  = params[:verification_record].to_unsafe_h.transform_keys(&:to_s)
      data_fields  = record_hash.select { |k, _| k.start_with?("data_") }

      structured_data = {}

      data_fields.each do |key, value|
        parts = key.sub(/^data_/, "").split("_", 2)
        next if parts.empty?

        if parts.size == 2
          section, field = parts
          structured_data[section] ||= {}
          structured_data[section][field] = value
        else
          structured_data[parts.first] = value
        end
      end

      # Normalize known record types
      case record_hash["record_type"]
      when "property"
        structured_data["property"]  ||= {}
        structured_data["valuation"] ||= {}
        structured_data["buyer"]     ||= {}
        structured_data["seller"]    ||= {}
        structured_data["legal"]     ||= {}
      when "business"
        structured_data["business"]  ||= {}
        structured_data["owner"]     ||= {}
        structured_data["registration"] ||= {}
      when "education"
        structured_data["education"] ||= {}
      when "health"
        structured_data["health"] ||= {}
      when "bank"
        structured_data["bank"] ||= {}
      end

      # Deep merge with schema defaults
      base[:data] = default_template_for(record_hash["record_type"]).deep_merge(structured_data)

      Rails.logger.info "Merged structured data: #{base[:data].inspect}"
      base
    end

    def set_record
      @record = current_citizen.verification_records.find(params[:id])
    end

    def set_defaults
      params[:verification_record][:status]       ||= "pending"
      params[:verification_record][:source]       ||= "citizen_portal"
      params[:verification_record][:access_level] ||= "private_access"
    end
  end
end
