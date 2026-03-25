# app/controllers/api/v1/users_controller.rb
module Api
  module V1
    class UsersController < Api::V1::BaseController
      include ResponseSigner
      before_action :authenticate_partner!
      before_action :set_user, only: %i[show verification_records]

      # ============================================================
      # GET /api/v1/users/:id
      # ============================================================
      def show
        payload = ActiveModelSerializers::SerializableResource.new(
          @user, serializer: UserSerializer
        ).as_json

        sign_response(payload)
        render json: payload
      rescue => e
        Rails.logger.error("[API::UsersController#show] #{e.class}: #{e.message}")
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      # ============================================================
      # GET /api/v1/users/:bonid/bonid_profile
      # ============================================================
      def bonid_profile
        bonid_param = params[:id]

        submission = IdentitySubmission
                      .includes(:user)
                      .where(bonid: bonid_param)
                      .order(verified_at: :desc)
                      .first

        return render json: { error: "User not found" }, status: :not_found unless submission&.user
        user = submission.user

        payload = {
          core: core_data(user, submission),
          address: address_data(user),
          documents: document_data(submission),
          meta: {
            verified_at: submission.verified_at,
            partner: @current_partner.name,
            bonid: user.bonid,
            status: submission.status,
            api_timestamp: Time.current
          }
        }

        render json: payload, status: :ok
      rescue => e
        Rails.logger.error("[API::UsersController#bonid_profile] #{e.class}: #{e.message}")
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      # ============================================================
      # GET /api/v1/users/:id/verification_records
      # ============================================================
      def verification_records
        records = @user.verification_records.order(created_at: :desc)

        payload = ActiveModelSerializers::SerializableResource.new(
          records,
          each_serializer: lambda { |record, _|
            record.record_type == "business" ?
              BusinessVerificationSerializer :
              VerificationRecordSerializer
          }
        ).as_json

        sign_response(payload)
        render json: payload
      rescue => e
        Rails.logger.error("[API::UsersController#verification_records] #{e.class}: #{e.message}")
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      private

      # ------------------------------------------------------------------
      # Partner authentication (middleware already sets env["current_partner"])
      # ------------------------------------------------------------------
      def authenticate_partner!
        @current_partner = request.env["current_partner"]
        render(json: { error: "Unauthorized partner" }, status: :unauthorized) unless @current_partner
      rescue => e
        Rails.logger.error("[API::UsersController#authenticate_partner!] #{e.class}: #{e.message}")
        render json: { error: "Internal authentication error" }, status: :internal_server_error
      end

      # ------------------------------------------------------------------
      # Utility: find user safely for non-BonID endpoints
      # ------------------------------------------------------------------
      def set_user
        @user = User.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "User not found" }, status: :not_found
      rescue => e
        Rails.logger.error("[API::UsersController#set_user] #{e.class}: #{e.message}")
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      # ------------------------------------------------------------------
      # Data Builders
      # ------------------------------------------------------------------
      def core_data(user, submission)
        {
          bonid: user.bonid,
          full_name: "#{user.first_name} #{user.last_name}",
          sex: user.sex,
          dob: user.dob,
          id_type: user.id_type,
          id_number: user.id_number,
          marital_status: user.marital_status,
          email: user.email,
          phone: user.phone,
          issue_date: submission.id_issued_on,
          expiry_date: submission.id_expires_on
        }
      end

      def address_data(user)
        addr = user.address
        return {} unless addr

        {
          street_address: addr.street_address,
          locality: addr.locality,
          commune: addr.commune&.name,
          arrondissement: addr.commune&.arrondissement&.name,
          department: addr.commune&.arrondissement&.department&.name,
          postal_code: addr.postal_code
        }
      end

      def document_data(submission)
        attachments = {
          selfie: "selfie_url",
          cin_front: "cin_front_url",
          cin_back: "cin_back_url",
          passport: "passport_url",
          proof_of_address: "proof_of_address_url"
        }

        attachments.each_with_object({}) do |(field, key), hash|
          hash[key.to_sym] = url_for(submission.public_send(field)) if submission.public_send(field).attached?
        end
      end

      def social_data(user)
        user.social_handles.present? ? user.social_handles.as_json(only: %i[platform handle verified]) : []
      end

      def bank_data(user)
        user.bank_profiles.present? ?
          user.bank_profiles.as_json(only: %i[wallet_provider account_number bank_name iban swift_code verified]) :
          []
      end


      def emergency_data(user)
        ec = user.emergency_contacts.first
        return {} unless ec

        {
          full_name: ec.full_name,
          relationship: ec.relationship,
          phone: ec.phone,
          email: ec.email
        }
      end

      def signature_data(submission)
        return {} unless submission.signature.attached?
        { url: url_for(submission.signature) }
      end
    end
  end
end
