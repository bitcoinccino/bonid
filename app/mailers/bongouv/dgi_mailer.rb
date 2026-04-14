# frozen_string_literal: true

# ==========================================================================
# BonGouv::DgiMailer — Email receipts for DGI payments.
#
# Sends a cryptographically sealed receipt to the citizen's email
# after successful payment. Includes:
#   - DGI header (Republic of Haiti)
#   - Citizen info (masked BonID + verified badge)
#   - Filing details + payment breakdown
#   - BonGouv digital seal (Ed25519 signed)
#   - Verification QR code link
#
# Usage:
#   BonGouv::DgiMailer.payment_receipt(@payment).deliver_later
# ==========================================================================
module Bongouv
  class DgiMailer < ApplicationMailer
    layout "mailer"
    default from: "BonGouv DGI <dgi@verifyem.ht>"
    helper ApplicationHelper

    # ----------------------------------------------------------------
    # PAYMENT RECEIPT — sent after successful payment
    # ----------------------------------------------------------------
    def payment_receipt(payment)
      @payment = payment
      @user = payment.user
      @record = payment.verification_record
      @submission = @user.identity_submissions&.find_by(status: "approved")

      # Seal data
      @seal = payment.provider_response&.dig("bongouv_seal")
      @verify_url = payment.seal_verify_url

      # Reviewing agent (if record was reviewed)
      if @record&.data&.dig("reviewed_by").present?
        @agent = User.find_by(email: @record.data["reviewed_by"])
      end
      @partner = @record&.partner

      # Layout config
      @email_product = "bongouv"
      @email_badge = "RESI PEMAN"

      @receipt_url = receipt_citizens_dgi_payment_url(payment)

      mail(
        to: @user.email,
        subject: "Resi Peman DGI — #{payment.form_type_label} — #{payment.formatted_total}"
      )
    end

    # ----------------------------------------------------------------
    # FILING CONFIRMATION — sent when a citizen submits a form
    # ----------------------------------------------------------------
    def filing_confirmation(record)
      @record = record
      @user = record.user
      @form_label = Citizens::DgiController::FORM_LABELS[record.record_type]

      @email_product = "bongouv"
      @email_badge = "DEKLARASYON"

      mail(
        to: @user.email,
        subject: "Deklarasyon Soumèt — #{@form_label&.dig(:title)} — #{record.data['declaration_number']}"
      )
    end

    # ----------------------------------------------------------------
    # REVIEW COMPLETE — sent when DGI agent approves/rejects
    # ----------------------------------------------------------------
    def review_complete(record, status)
      @record = record
      @user = record.user
      @status = status
      @form_label = Citizens::DgiController::FORM_LABELS[record.record_type]

      @email_product = "bongouv"
      @email_badge = status == "verified" ? "APWOUVE" : "REJTE"
      @email_alert = status == "verified" ? "Deklarasyon ou apwouve!" : "Deklarasyon ou rejte"
      @email_alert_type = status == "verified" ? "success" : "danger"

      mail(
        to: @user.email,
        subject: "#{status == 'verified' ? 'Apwouve' : 'Rejte'} — #{@form_label&.dig(:title)} — #{record.data['declaration_number']}"
      )
    end
  end
end
