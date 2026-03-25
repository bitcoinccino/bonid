# app/controllers/citizens/profiles_controller.rb
module Citizens
  class ProfilesController < BaseController
    before_action :authenticate_citizen!
    before_action :set_citizen
    before_action :set_identity_verified
    before_action :build_nested_associations, only: [ :edit ]
    before_action :preload_departments, only: [ :edit, :update ]

    def show; end

    def edit
      @citizen.build_address_with_defaults if @citizen.address.blank?
    end

    def update
      @citizen.build_address_with_defaults if @citizen.address.blank?

      # Normalize phone: prepend Haiti country code if user entered local number
      if params.dig(:user, :phone).present?
        phone = params[:user][:phone].gsub(/\s+/, "")
        params[:user][:phone] = "+509#{phone}" unless phone.start_with?("+")
      end

      was_incomplete = !@citizen.profile_complete?

      if @citizen.update(user_params)
        if @citizen.bonid.blank? && @citizen.profile_complete?
          @citizen.generate_bonid!
        end

        already_verified = @citizen.identity_submissions.exists?(status: :approved)

        notice =
          if was_incomplete && @citizen.profile_complete?
            if already_verified
              "✅ Profile updated successfully."
            else
              "🎉 Profile completed! You can now submit for BonID verification."
            end
          else
            "✅ Profile updated successfully."
          end

        redirect_path =
          if was_incomplete && @citizen.profile_complete? && !already_verified
            new_citizens_identity_submission_path
          else
            citizens_dashboard_path
          end

        redirect_to redirect_path, notice: notice
      else
        log_validation_failure
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_citizen
      @citizen = current_citizen
      return if @citizen

      redirect_to new_citizens_session_path,
                  alert: "Session expired. Please sign in again."
    end

    def set_identity_verified
      @identity_verified = @citizen&.identity_submissions&.exists?(status: :approved) || false
    end

    # Core identity fields locked after verification (verified against gov ID)
    # Only name, DOB, sex, nationality — the rest (ID docs, address, phone, etc.) stay editable
    LOCKED_FIELDS = %i[
      first_name middle_name last_name
      sex dob nationality
    ].freeze

    # UI-only builds (NO persistence)
    def build_nested_associations
      @citizen.build_address_with_defaults if @citizen.address.blank?

      %i[physical_profile health_profile].each do |relation|
        @citizen.public_send("build_#{relation}") if @citizen.public_send(relation).blank?
      end

      %i[emergency_contacts social_handles bank_profiles].each do |relation|
        @citizen.public_send(relation).build if @citizen.public_send(relation).empty?
      end
    end

    def preload_departments
      @departments =
        Department
          .includes(arrondissements: { communes: :communal_sections })
          .order(:name)
    end

    # STRONG PARAMS (sensitive fields should be encrypted in model)
    def user_params
      permitted = params.require(:user).permit(
        :photo,
        :prefix, :suffix,
        :first_name, :middle_name, :last_name,
        :sex, :dob, :phone, :marital_status,
        :id_type, :id_number, :cin_unique_id,
        :birth_department_id, :birth_commune_id,
        :id_issued_on, :id_expires_on,
        :document_issuer, :nationality, :ninu,

        address_attributes: [
          :id, :street_address, :postal_code, :locality, :country,
          :department_id, :arrondissement_id, :commune_id, :communal_section_id
        ],

        emergency_contacts_attributes: [
          :id, :name, :phone, :email, :relation,
          :address, :bonid, :visibility,
          :verification_status, :_destroy
        ],

        family_members_attributes: [
          :id, :relationship, :first_name, :middle_name, :last_name,
          :date_of_birth, :place_of_birth, :nationality, :alive,
          :linked_bonid, :date_of_death, :guardian_type,
          :birth_department_id, :birth_commune_id, :_destroy
        ],

        social_handles_attributes: [
          :id, :platform, :handle, :active,
          :since, :until, :visibility,
          :verification_status, :_destroy
        ],

        health_profile_attributes: [
          :id, :blood_type,
          { allergies: [] }, :allergies_other,
          { chronic_conditions: [] }, :chronic_conditions_other,
          { medications: [] }, :medications_other,
          :organ_donor
        ],

        physical_profile_attributes: [
          :id, :weight_kg, :height_cm, :race,
          :eye_color, :hair_color, :hair_style,
          :tattoos, :scars, :body_type,
          :skin_tone, :facial_hair, :handedness
        ],

        bank_profiles_attributes: [
          :id, :bank_id, :bank_name, :account_number,
          :account_type, :account_source, :currency,
          :branch_name, :opened_on, :closed_on,
          :access_level, :currently_open,
          :linked_at, :swift_code,
          :wallet_address, :wallet_provider,
          :chain, :status, :_destroy
        ]
      )

      # Server-side protection: strip locked fields if identity is verified
      if @identity_verified
        LOCKED_FIELDS.each { |field| permitted.delete(field) }
      end

      permitted
    end

    def log_validation_failure
      Rails.logger.warn(
        "⚠️ Profile update failed for Citizen #{@citizen.id}: #{@citizen.errors.full_messages.join(', ')}"
      )
      # Log bank profile specific errors
      @citizen.bank_profiles.each_with_index do |bp, idx|
        if bp.errors.any?
          Rails.logger.warn("⚠️ BankProfile[#{idx}] errors: #{bp.errors.full_messages.join(', ')}")
        end
      end
      flash.now[:alert] =
        @citizen.errors.full_messages.to_sentence.presence ||
        "⚠️ Could not update profile."
    end
  end
end
