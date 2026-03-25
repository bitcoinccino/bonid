# frozen_string_literal: true

module Api
  module V1
    class TransactionConsentsController < BaseController
      # Citizen decide action uses OTP as auth — no API key needed
      skip_before_action :authenticate_partner_or_token!, only: [:decide]
      skip_before_action :set_current_context, only: [:decide]
      skip_before_action :enforce_scope!, only: [:decide]

      # ===========================================================
      # POST /api/v1/transaction_consents
      # Partner requests citizen consent for a transaction
      # Auth: X-Partner-Api-Key
      # ===========================================================
      def create
        citizen = User.find_by(bonid: params[:bonid]&.strip&.upcase)
        return render json: { error: "Citizen not found" }, status: :not_found unless citizen

        type = params[:transaction_type].to_s
        unless TransactionConsent::VALID_TRANSACTION_TYPES.include?(type)
          return render json: {
            error: "Invalid transaction_type",
            valid_types: TransactionConsent::VALID_TRANSACTION_TYPES
          }, status: :unprocessable_entity
        end

        unless @partner.transaction_type_allowed?(type)
          return render json: {
            status: "forbidden",
            error: "Partner not authorized for transaction type '#{type}'",
            allowed_types: @partner.effective_allowed_transaction_types,
            timestamp: Time.current.iso8601
          }, status: :forbidden
        end

        scopes = Array(params[:scopes])
        if scopes.empty?
          return render json: { error: "Missing scopes" }, status: :unprocessable_entity
        end

        consent = TransactionConsentService.create_request!(
          partner: @partner,
          citizen: citizen,
          params: {
            transaction_type: type,
            scopes: scopes,
            amount: params[:amount],
            currency: params[:currency],
            description: params[:description],
            reference_id: params[:reference_id],
            callback_url: params[:callback_url],
            ip: request.remote_ip,
            ua: request.user_agent
          }
        )

        render json: {
          status: "pending",
          consent_token: consent.consent_token,
          transaction_type: consent.transaction_type,
          expires_at: consent.expires_at.iso8601,
          ttl_seconds: (consent.expires_at - Time.current).to_i,
          message: "Consent request sent to citizen. Awaiting approval."
        }, status: :created
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        if e.message.include?("reference_id") || e.message.include?("idx_tx_consent_citizen_partner_ref")
          render json: { error: "Consent already requested for this transaction" }, status: :unprocessable_entity
        else
          render json: { error: e.message }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error("[TransactionConsents#create] #{e.class}: #{e.message}")
        render json: { error: "Internal error" }, status: :internal_server_error
      end

      # ===========================================================
      # POST /api/v1/transaction_consents/:consent_token/decide
      # Citizen approves or denies with OTP
      # Auth: None (OTP is the auth)
      # ===========================================================
      def decide
        consent = TransactionConsent.find_by(consent_token: params[:consent_token])
        return render json: { error: "Consent not found" }, status: :not_found unless consent

        unless consent.pending?
          return render json: {
            error: "Consent already #{consent.status}",
            status: consent.status
          }, status: :unprocessable_entity
        end

        otp_code = params[:otp].to_s.strip
        decision = params[:decision].to_s.strip.downcase

        unless %w[approve deny].include?(decision)
          return render json: { error: "Invalid decision. Use 'approve' or 'deny'." }, status: :unprocessable_entity
        end

        if otp_code.blank?
          return render json: { error: "OTP code is required" }, status: :unprocessable_entity
        end

        result = TransactionConsentService.verify_and_decide!(
          consent: consent,
          otp_code: otp_code,
          decision: decision,
          ip: request.remote_ip
        )

        render json: result.summary, status: :ok
      rescue TransactionConsentService::ExpiredError
        render json: { error: "Consent has expired. Request a new one." }, status: :gone
      rescue TransactionConsentService::LockedError
        render json: { error: "Too many failed attempts. Request a new consent." }, status: :too_many_requests
      rescue TransactionConsentService::InvalidOtpError => e
        render json: { error: e.message }, status: :unauthorized
      rescue => e
        Rails.logger.error("[TransactionConsents#decide] #{e.class}: #{e.message}")
        render json: { error: "Internal error" }, status: :internal_server_error
      end

      # ===========================================================
      # GET /api/v1/transaction_consents/:consent_token
      # Partner polls consent status
      # Auth: X-Partner-Api-Key
      # ===========================================================
      def show
        consent = TransactionConsent.find_by(
          consent_token: params[:consent_token],
          partner_id: @partner.id
        )
        return render json: { error: "Consent not found" }, status: :not_found unless consent

        render json: consent.summary, status: :ok
      end
    end
  end
end
