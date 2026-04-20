# frozen_string_literal: true

# Bureau du Contentieux Electoral National (BCEN) — dispute review surface.
#
# The Décret Électoral gives rejected candidates, parties, and citizens the
# right to challenge CEP decisions (Articles 189+). Today BonID has the model
# for those filings (ElectionDispute) but no staff-side surface to work them.
# This controller is that surface.
#
# Access is gated by CepAdminGate — only AdminUser-level :super_admin or
# :cep_admin Rolify roles can adjudicate disputes here.
module Election
  module Admin
    class DisputesController < ::Admin::BaseController
      include Election::Admin::CepAdminGate

      before_action :set_election
      before_action :set_dispute, only: %i[show start_review schedule_hearing decide close]

      # GET /admin/election/:election_id/disputes
      def index
        scope = ElectionDispute.where(election: @election)
        scope = scope.where(status: params[:status])             if params[:status].present?
        scope = scope.where(dispute_type: params[:dispute_type]) if params[:dispute_type].present?
        scope = scope.where(priority: params[:priority])         if params[:priority].present?
        if params[:search].present?
          scope = scope.where(
            "reference_code ILIKE :q OR filed_by_name ILIKE :q OR subject ILIKE :q",
            q: "%#{params[:search]}%"
          )
        end

        @stats    = ElectionDispute.stats_for(@election.id)
        @disputes = scope.order(Arel.sql("CASE priority WHEN 'urgent' THEN 0 ELSE 1 END"))
                         .order(filed_at: :desc)
                         .page(params[:page]).per(25)
      end

      # GET /admin/election/:election_id/disputes/:id
      def show; end

      # POST /admin/election/:election_id/disputes/:id/start_review
      def start_review
        admin = current_admin_user
        @dispute.start_review!(
          officer_name:  admin&.email,
          officer_bonid: bridge_bonid_for(admin)
        )
        redirect_to admin_election_election_dispute_path(@election.id, @dispute),
                    notice: "Revizyon kòmanse pou #{@dispute.reference_code}."
      end

      # POST /admin/election/:election_id/disputes/:id/schedule_hearing
      def schedule_hearing
        hearing_at = parse_hearing_at(params[:hearing_at])
        if hearing_at.nil? || hearing_at < Time.current
          redirect_to admin_election_election_dispute_path(@election.id, @dispute),
                      alert: "Dat odyans la pa valid (dwe nan lavni)."
          return
        end

        @dispute.schedule_hearing!(hearing_date: hearing_at)
        redirect_to admin_election_election_dispute_path(@election.id, @dispute),
                    notice: "Odyans pwograme pou #{hearing_at.strftime('%d %b %Y %H:%M')}."
      end

      # POST /admin/election/:election_id/disputes/:id/decide
      def decide
        decision_text = params[:decision].to_s.strip
        decision_type = params[:decision_type].to_s
        unless ElectionDispute::DECISION_TYPES.include?(decision_type)
          redirect_to admin_election_election_dispute_path(@election.id, @dispute),
                      alert: "Tip desizyon pa valid."
          return
        end
        if decision_text.blank?
          redirect_to admin_election_election_dispute_path(@election.id, @dispute),
                      alert: "Tèks desizyon obligatwa."
          return
        end

        @dispute.decide!(decision_text: decision_text, decision_type: decision_type)
        redirect_to admin_election_election_dispute_path(@election.id, @dispute),
                    notice: "Desizyon anrejistre. Apèl posib jiska #{@dispute.appeal_deadline.strftime('%d %b %Y')}."
      end

      # POST /admin/election/:election_id/disputes/:id/close
      def close
        @dispute.close!
        redirect_to admin_election_election_disputes_path(@election.id),
                    notice: "Kontestasyon #{@dispute.reference_code} fèmen."
      end

      private

      def set_election
        @election = BonvoteElection.find(params[:election_id])
      end

      def set_dispute
        @dispute = ElectionDispute.where(election: @election).find(params[:id])
      end

      def parse_hearing_at(raw)
        return nil if raw.blank?
        Time.zone.parse(raw.to_s)
      rescue ArgumentError
        nil
      end

      # Best-effort: surface the CEP officer's BonID on the audit trail when
      # their AdminUser email matches a User with a verified BonID.
      def bridge_bonid_for(admin)
        return nil unless admin&.email
        User.find_by(email: admin.email)&.bonid
      end
    end
  end
end
