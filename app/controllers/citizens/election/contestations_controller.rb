# frozen_string_literal: true

# Article 192 of the Décret Électoral (1er Décembre 2025):
# "Dans les quarante-huit (48) heures de l'affichage des listes préliminaires,
#  tout candidat, parti politique, ou regroupement de partis politiques,
#  dûment enregistré, peut déposer par-devant le tribunal électoral
#  compétent une contestation..."
#
# This controller lets a verified citizen file that contestation from within
# BonID against a candidate who is currently on the liste préliminaire. The
# filing creates an ElectionDispute with `dispute_type: "challenge"` that the
# BCEN adjudicator surface (election/admin/disputes) picks up.
#
# Gating:
#   - Citizen must be BonID-verified.
#   - Target candidate must be in `preliminary_listed` state.
#   - The 48-hour contestation window must still be open.
module Citizens
  module Election
    class ContestationsController < BaseController
      before_action :require_verified_bonid!
      before_action :set_candidate

      # GET /citizens/election/candidates/:election_candidate_id/contest/new
      def new
        return redirect_to_candidates_with_alert("Kandida a pa sou lis preliminè la.") unless preliminary?
        return redirect_to_candidates_with_alert("Fenèt kontestasyon 48h fèmen.") unless window_open?
      end

      # POST /citizens/election/candidates/:election_candidate_id/contest
      def create
        return redirect_to_candidates_with_alert("Kandida a pa sou lis preliminè la.") unless preliminary?
        return redirect_to_candidates_with_alert("Fenèt kontestasyon 48h fèmen.") unless window_open?

        subject = params.dig(:contestation, :subject).to_s.strip
        details = params.dig(:contestation, :details).to_s.strip

        if subject.blank? || details.blank?
          flash.now[:alert] = "Tit ak detay obligatwa."
          render :new, status: :unprocessable_entity and return
        end

        dispute = ElectionDispute.new(
          election: @candidate.election,
          election_candidate: @candidate,
          constituency: @candidate.election_constituency,
          dispute_type: "challenge",
          filed_by_type: "citizen",
          filed_by_name: current_citizen.full_name,
          filed_by_bonid: current_citizen.bonid,
          subject: subject,
          description: details,
          department_code: @candidate.department_code,
          status: "filed",
          priority: "normal"
        )

        if dispute.save
          redirect_to election_public_candidates_path(election_id: @candidate.election_id),
                      notice: "Kontestasyon w depoze. Referans: #{dispute.reference_code}."
        else
          flash.now[:alert] = dispute.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_candidate
        @candidate = ElectionCandidate.find(params[:election_candidate_id])
      end

      def preliminary?
        @candidate.registration_status == "preliminary_listed"
      end

      def window_open?
        @candidate.contestation_window_open?
      end

      def redirect_to_candidates_with_alert(msg)
        redirect_to election_public_candidates_path(election_id: @candidate.election_id), alert: msg
      end
    end
  end
end
