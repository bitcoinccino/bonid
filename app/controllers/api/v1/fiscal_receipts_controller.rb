# frozen_string_literal: true

# 🇭🇹 BonID — Fiscal Receipt API Controller
# =============================================
# Handles fiscal receipt operations for partner agencies (DGI, Immigration).
#
# Endpoints:
#   POST   /api/v1/fiscal_receipts/lookup   — Find a receipt by receipt_number
#   PATCH  /api/v1/fiscal_receipts/consume  — Mark a receipt as consumed (one-time use)
#
# Auth: Standard partner API key (X-Partner-Api-Key) or OAuth Bearer token.
# Scope: fiscal_receipts:consume (required for consume action)
# =============================================

module Api
  module V1
    class FiscalReceiptsController < Api::V1::BaseController
      before_action :find_fiscal_receipt, only: %i[lookup consume]

      # ============================================================
      # GET /api/v1/fiscal_receipts/lookup?receipt_number=DGI-2026-PAP-0048721
      # ============================================================
      # Returns the fiscal receipt record and its consumption status.
      # Used by Immigration (or any agency) to verify a receipt exists
      # and whether it has already been consumed.
      # ============================================================
      def lookup
        render json: {
          status: "found",
          receipt: {
            id:              @record.id,
            receipt_number:  @record.receipt_number,
            tax_type:        @record.tax_type,
            amount_htg:      @record.amount_htg,
            payment_date:    @record.payment_date,
            fiscal_year:     @record.fiscal_year,
            dgi_office_code: @record.dgi_office_code,
            payer_name:      @record.payer_name,
            payer_bonid:     @record.payer_bonid,
            status:          @record.status,
            verified_at:     @record.verified_at&.iso8601,
            consumable:      @record.consumable?,
            consumed:        @record.consumed?,
            consumption:     @record.consumed? ? {
              consumed_at:            @record.consumed_at,
              consumed_by_agency:     @record.consumed_by_agency,
              consumed_by_officer_id: @record.consumed_by_officer_id
            } : nil
          },
          citizen: citizen_summary,
          timestamp: Time.current.iso8601
        }, status: :ok
      end

      # ============================================================
      # PATCH /api/v1/fiscal_receipts/consume
      # ============================================================
      # Marks a fiscal receipt as consumed by the calling agency.
      # Once consumed, the receipt cannot be reused — this is the core
      # mechanism that prevents passport stamp fraud.
      #
      # Params:
      #   receipt_number (required) — DGI receipt number
      #   officer_id     (required) — ID of the officer consuming the receipt
      #
      # Returns 200 on success, 422 if already consumed, 404 if not found.
      # ============================================================
      def consume
        officer_id = params[:officer_id].to_s.strip

        if officer_id.blank?
          return render json: {
            status: "error",
            error: "officer_id is required",
            timestamp: Time.current.iso8601
          }, status: :bad_request
        end

        unless @record.consumable?
          message = if @record.consumed?
            "Receipt #{@record.receipt_number} was already consumed on " \
            "#{@record.consumed_at} by #{@record.consumed_by_agency} " \
            "(officer: #{@record.consumed_by_officer_id})"
          else
            "Receipt #{@record.receipt_number} is not in a consumable state (status: #{@record.status})"
          end

          return render json: {
            status: "rejected",
            error: message,
            receipt_number: @record.receipt_number,
            consumed: @record.consumed?,
            timestamp: Time.current.iso8601
          }, status: :unprocessable_entity
        end

        # Consume the receipt (atomic update)
        @record.consume!(
          agency:     @partner&.name || "unknown",
          officer_id: officer_id,
          metadata:   {
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            partner_id: @partner&.id
          }
        )

        # Log the consumption event for audit trail
        log_consumption_event!(officer_id)

        render json: {
          status: "consumed",
          message: "Receipt #{@record.receipt_number} consumed successfully",
          receipt: {
            receipt_number:  @record.receipt_number,
            tax_type:        @record.tax_type,
            amount_htg:      @record.amount_htg,
            payer_name:      @record.payer_name,
            payer_bonid:     @record.payer_bonid,
            consumed_at:     @record.consumed_at,
            consumed_by:     @partner&.name
          },
          citizen: citizen_summary,
          timestamp: Time.current.iso8601
        }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
          status: "error",
          error: e.message,
          timestamp: Time.current.iso8601
        }, status: :unprocessable_entity
      end

      private

      # ============================================================
      # Find the fiscal receipt by receipt_number (JSONB query)
      # ============================================================
      def find_fiscal_receipt
        receipt_number = params[:receipt_number].to_s.strip

        if receipt_number.blank?
          return render json: {
            status: "error",
            error: "receipt_number is required",
            timestamp: Time.current.iso8601
          }, status: :bad_request
        end

        @record = VerificationRecord
          .where(record_type: "fiscal_receipt")
          .where("data->'receipt'->>'receipt_number' = ?", receipt_number)
          .first

        unless @record
          render json: {
            status: "not_found",
            error: "No fiscal receipt found with number: #{receipt_number}",
            timestamp: Time.current.iso8601
          }, status: :not_found
        end
      end

      # ============================================================
      # Citizen summary (photo + name for visual confirmation)
      # ============================================================
      def citizen_summary
        user = @record.user
        return nil unless user

        verified = user.verified_identity_submission
        photo_url = if verified&.selfie&.attached?
          Rails.application.routes.url_helpers.rails_blob_url(verified.selfie, only_path: false)
        end

        {
          bonid:      user.bonid,
          first_name: user.first_name,
          last_name:  user.last_name,
          photo_url:  photo_url
        }
      end

      # ============================================================
      # Audit trail: log consumption as a partner audit event
      # ============================================================
      def log_consumption_event!(officer_id)
        return unless @partner

        PartnerAuditLog.log!(
          @partner,
          nil, # no admin actor — this is an API action
          "fiscal_receipt_consumed",
          "Receipt #{@record.receipt_number} consumed by officer #{officer_id} " \
          "for citizen #{@record.payer_bonid} (#{@record.tax_type}, #{@record.amount_htg} HTG)"
        )
      rescue => e
        Rails.logger.error("[FiscalReceipts#log_consumption] #{e.class}: #{e.message}")
      end
    end
  end
end
