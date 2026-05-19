# frozen_string_literal: true

# Citizens::Election::ReceiptsController
#
# Download / print the BonID voter-registration receipt as a PDF. The
# receipt carries the BVT reference, citizen identity, assigned BV, and a
# QR code encoding `VoterEligibilityRecord#receipt_qr_payload` so poll
# workers can scan it at the polling station.
#
# Idempotent: regenerates the PDF if the stored attachment is missing or
# older than the record's `receipt_generated_at` timestamp.
module Citizens
  module Election
    class ReceiptsController < BaseController
      before_action :load_record!

      # GET /citizens/election/receipt/download.pdf
      def download
        bytes = ensure_pdf!
        send_data bytes,
                  filename: "resi-vote-#{@record.voter_reference}.pdf",
                  type: "application/pdf",
                  disposition: "attachment"
      end

      # GET /citizens/election/receipt/print.pdf — inline so the browser can
      # open it in its native PDF viewer with a print button ready.
      def print
        bytes = ensure_pdf!
        send_data bytes,
                  filename: "resi-vote-#{@record.voter_reference}.pdf",
                  type: "application/pdf",
                  disposition: "inline"
      end

      private

      def load_record!
        @election = active_election ||
                    BonvoteElection.where(status: "draft").order(:election_date).first

        unless @election
          redirect_to citizens_election_enrollment_path,
                      alert: "Pa gen eleksyon aktif."
          return
        end

        @record = VoterEligibilityRecord.find_by(
          bonvote_election: @election,
          user_id: current_citizen.id
        )

        return if @record&.eligible?

        redirect_to citizens_election_enrollment_path,
                    alert: "Ou pa ko anrejistre pou eleksyon sa a."
      end

      # Returns freshly-rendered or cached PDF bytes. When the ActiveStorage
      # attachment exists and the record hasn't changed since it was
      # generated, we stream the cached blob. Otherwise regenerate.
      def ensure_pdf!
        needs_regen = !@record.receipt_pdf.attached? ||
                      @record.receipt_generated_at.blank? ||
                      @record.updated_at > @record.receipt_generated_at

        if needs_regen
          # ::Election forces top-level constant lookup — without the leading
          # `::`, Ruby resolves Election relative to the enclosing namespace
          # (Citizens::Election::Election::VoterReceiptPdfService → NameError).
          return ::Election::VoterReceiptPdfService.call(
            @record,
            host:     request.host_with_port,
            protocol: request.protocol.sub("://", "")
          )
        end

        @record.receipt_pdf.download
      end
    end
  end
end
