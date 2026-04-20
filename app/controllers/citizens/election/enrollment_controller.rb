# frozen_string_literal: true

# Citizens::Election::EnrollmentController — "Eleksyon Mwen" unified state page.
#
# Single page a citizen visits to answer: "Am I registered for the next
# election? If not, can I register here?"
#
# States (rendered in `show`):
#   - no_election            → no active or upcoming election
#   - voted                  → already cast a ballot; show verify link
#   - registered             → show BV card + preferred channel
#   - registrable_digital    → eligible, not yet on the roll → CTA to enroll
#   - registrable_in_person  → eligible but this election doesn't accept online registration
#   - ineligible             → too young / BonID not verified / CIN missing
#
# `create` is the self-service enrollment action. It is idempotent: calling
# it twice simply returns the same record, which makes it safe under double-
# click or back/forward navigation.
module Citizens
  module Election
    class EnrollmentController < BaseController
      before_action :load_election

      def show
        @record              = find_voter_record
        @ineligibility_reason = ineligibility_reason
        @state               = compute_state
      end

      def create
        unless @election
          redirect_to citizens_election_enrollment_path,
                      alert: "Pa gen eleksyon aktif."
          return
        end

        preferred = enrollment_params[:preferred_channel].to_s
        preferred = "in_person" unless VoterEligibilityRecord::PREFERRED_CHANNELS.include?(preferred)

        @record = VoterEligibilityRecord.register_digital_voter!(
          election: @election,
          user: current_citizen,
          preferred_channel: preferred
        )

        if @record.eligible?
          # Fire-and-forget PDF generation so the receipt is ready when the
          # citizen lands on the :registered state. Silent failure here is
          # fine — the ReceiptController regenerates on demand.
          begin
            Election::VoterReceiptPdfService.call(
              @record,
              host:     request.host_with_port,
              protocol: request.protocol.sub("://", "")
            )
          rescue StandardError => e
            Rails.logger.warn "[Enrollment] Receipt PDF generation failed: #{e.class}: #{e.message}"
          end

          flash[:just_registered] = true
          redirect_to citizens_election_enrollment_path,
                      notice: "Ou anrejistre avèk siksè pou eleksyon sa a."
        else
          redirect_to citizens_election_enrollment_path,
                      alert: "Nou pa t ka enskri ou: #{@record.ineligibility_label}"
        end
      rescue VoterEligibilityRecord::DigitalEnrollmentNotAllowedError => e
        redirect_to citizens_election_offices_path,
                    alert: "#{e.message} Ale nan yon biwo BonID pou enskri an pèsòn."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to citizens_election_enrollment_path,
                    alert: "Erè pandan enskripsyon: #{e.message}"
      end

      private

      # Explicit allowlist for the enrollment form. Guards against future
      # refactors (nested forms, params.permit!, accidental inclusion of
      # `polling_station_id` / `cin_number` etc.) — BV assignment must stay
      # server-side via VoterEligibilityRecord.assign_polling_station!.
      def enrollment_params
        params.permit(:preferred_channel)
      end

      # Prefers open; falls back to the nearest draft so the citizen can see
      # what's coming. No active-election? show the empty state.
      def load_election
        @election = active_election ||
                    BonvoteElection.where(status: "draft").order(:election_date).first
      end

      # Matches the link-back logic in register_digital_voter! — a voter may
      # already have an analog record keyed by CIN that hasn't been claimed.
      def find_voter_record
        return nil unless @election

        record = VoterEligibilityRecord.find_by(
          bonvote_election: @election,
          user_id: current_citizen.id
        )
        return record if record

        if current_citizen.cin_unique_id.present?
          VoterEligibilityRecord.find_by(
            bonvote_election: @election,
            cin_number: current_citizen.cin_unique_id,
            user_id: nil
          )
        end
      end

      def compute_state
        return :no_election unless @election
        return :voted      if @record&.has_voted?
        return :registered if @record&.eligible?

        reason = ineligibility_reason
        return :ineligible if reason

        :registrable_digital
      end

      # Returns a reason key if the citizen cannot self-enroll, else nil.
      # Uses the same precedence as apply_digital_eligibility! so the UI
      # matches what register_digital_voter! would stamp on the record.
      def ineligibility_reason
        return "no_cin" unless current_citizen.bonid_verified?
        return "no_cin" if current_citizen.id_number.blank?
        return "underage" if current_citizen.dob.blank? || current_citizen.age < 18

        nil
      end
    end
  end
end
