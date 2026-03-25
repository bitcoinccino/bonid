# app/controllers/partner_portal/schemas_controller.rb
module PartnerPortal
  class SchemasController < PartnerPortal::BaseController
    before_action :set_partner
    before_action :set_schema, only: %i[show edit update preview validate_sample preview_json share_data]

    # === CRUD ===========================================================
    def index
      @schemas = @partner.partner_schemas.order(created_at: :desc)
    end

    def new
      @schema = @partner.partner_schemas.new
    end

    def create
      @schema = @partner.partner_schemas.new(schema_params)
      if @schema.save
        redirect_to partner_portal_schemas_path,
                    notice: "Schema created successfully. Pending admin approval."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @schema.update(schema_params)
        redirect_to partner_portal_schemas_path,
                    notice: "Schema updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # === PREVIEW / VALIDATION ===========================================

    # Show preview form for this schema
    def preview
      @fields = Array(@schema.structure["fields"])
    end

    # Validate the submitted sample fields
    def validate_sample
      @fields = Array(@schema.structure["fields"])
      sample = params[:sample] || {}
      missing = @fields.filter_map do |f|
        (f["required"] && sample[f["key"]].blank?) ? (f["label"] || f["key"]) : nil
      end

      if missing.any?
        flash.now[:alert] = "Missing required fields: #{missing.join(', ')}"
        render :preview, status: :unprocessable_entity
      else
        flash.now[:notice] = "✅ All required fields are present!"
        render :preview
      end
    end

    # === LIVE JSON PREVIEW ==============================================

    # Generate live JSON structure that mimics VerificationRecord.data
    def preview_json
      @form_data = params[:data].permit!.to_h
      @record_json = build_verification_json(@schema, @form_data)

      respond_to do |format|
        format.turbo_stream
        format.html
        format.json { render json: @record_json }
      end
    end

    # === SHARE DATA (Interbank Sharing for Haitian Banks) ===============
    # Share validated schema data with any Haitian bank (e.g., Unibank from Sogebank)
    def share_data
      schema_id = params[:schema_id]
      @schema = @partner.partner_schemas.find(schema_id)

      # Validate schema ownership
      head :not_found unless @schema

      @form_data = params[:data].permit!.to_h
      unless params[:consent] == "true"
        render json: { error: "Explicit consent required for data sharing" }, status: :unprocessable_entity
        return
      end

      # Validate data against schema
      missing = validate_data_against_schema(@form_data, @schema.structure["fields"])
      if missing.any?
        render json: { error: "Missing required fields", missing: missing }, status: :unprocessable_entity
        return
      end

      # Build and encrypt JSON
      @record_json = build_verification_json(@schema, @form_data)
      encrypted_data = encrypt_json(@record_json)

      # Log for audit (BRH compliance)
      ShareLog.create!(
        partner_id: @partner.id,
        schema_id: schema_id,
        recipient_bank_id: params[:recipient_bank_id],
        data_token: encrypted_data[:token],
        consent_given: true,
        shared_data_preview: @record_json.slice(:record_type, :submitted_at)  # Log metadata only
      )

      # Send to recipient bank (async for scalability)
      ShareWebhookJob.perform_later(
        token: encrypted_data[:token],
        recipient_bank_id: params[:recipient_bank_id],
        sender_partner_id: @partner.id,
        shared_secret: encrypted_data[:shared_secret]
      )

      render json: {
        status: "shared",
        token: encrypted_data[:token],
        shared_with: params[:recipient_bank_id],
        expires_at: 24.hours.from_now.iso8601  # Token expires in 24h
      }, status: :ok
    end

    # === PRIVATE HELPERS ================================================
    private

    def set_partner
      @partner = current_partner_admin.partner
    end

    def set_schema
      @schema = @partner.partner_schemas.find(params[:id])
    end

    def schema_params
      params.require(:partner_schema).permit(
        :name, :record_type, :visibility, :version,
        structure: {}, validation_rules: {}
      )
    end

    def build_verification_json(schema, form_data)
      {
        record_type: schema.record_type,
        partner_id: schema.partner_id,
        version: schema.version,
        data: form_data.deep_symbolize_keys,
        submitted_at: Time.current.iso8601
      }
    end

    # NEW: Validate data against schema fields
    def validate_data_against_schema(form_data, fields)
      fields.filter_map do |field|
        next unless field["required"]
        form_data[field["key"]].blank? ? (field["label"] || field["key"]) : nil
      end
    end

    # NEW: Encrypt JSON for secure sharing
    def encrypt_json(json_data)
      shared_secret = ENV["SHARE_SECRET"] || SecureRandom.hex(32)  # In prod, use KMS
      iv = OpenSSL::Cipher::AES256.new(:CBC).random_iv

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = Digest::SHA256.digest(shared_secret)[0..31]
      cipher.iv = iv

      encrypted = cipher.update(json_data.to_json) + cipher.final
      token = Base64.urlsafe_encode64(encrypted + iv)

      { token: token, shared_secret: shared_secret }
    end

    # NEW: Job for async webhook to recipient bank
    class ShareWebhookJob < ApplicationJob
      def perform(token, recipient_bank_id, sender_partner_id)
        recipient = Partner.find(recipient_bank_id)  # Assuming Partner model for banks
        payload = { token: token, sender_id: sender_partner_id }

        HTTParty.post(
          recipient.webhook_url || "https://default-bank.ht/api/receive_share",
          body: payload.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end
    end
  end
end
