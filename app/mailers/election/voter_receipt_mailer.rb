# frozen_string_literal: true

module Election
  # Sends a citizen their voter-registration receipt PDF by email, so they
  # can print at a copy shop or archive outside the BonID app. The email
  # itself repeats the voter reference and BV assignment in plain text so
  # it's still usable if the PDF attachment strips in transit.
  class VoterReceiptMailer < ApplicationMailer
    default from: "bonvote@verifyem.ht"

    def registration_confirmation(record_id)
      @record   = VoterEligibilityRecord.find(record_id)
      @user     = @record.user
      @election = @record.bonvote_election

      return if @user&.email.blank?

      # Ensure the PDF exists on the record; if not, render it now.
      unless @record.receipt_pdf.attached?
        ::Election::VoterReceiptPdfService.call(@record, attach: true)
        @record.reload
      end

      if @record.receipt_pdf.attached?
        attachments["resi-vote-#{@record.voter_reference}.pdf"] = @record.receipt_pdf.download
      end

      mail(
        to:      @user.email,
        subject: "BonVote — Resi Enskripsyon Vòt #{@record.voter_reference}"
      )
    end
  end
end
