module PartnerPortal
  module LawEnforcement
    class OfficersController < PartnerPortal::LawEnforcement::BaseController
      layout "partner_portal/law_enforcement"
      before_action :set_partner
      before_action :set_officer, only: [ :show, :revoke, :reactivate ]

      def index
        # Unit-scoped admins only see officers in their unit
        @officers = apply_portal_officer_scope(@partner.officers)
                      .includes(user: :identity_submissions)
                      .order(created_at: :desc)
      end

      def show
        # Unit-scoped admins may not view officers from other units
        return unless enforce_unit_access_on_officer!(@officer)
        @incident_reports = @officer.incident_reports.order(created_at: :desc).limit(10)
      end

      def new
        @officer = User.new
      end

      def create
        # You'll likely use invitations, so this can delegate to Devise Invitable
        @officer = @partner.officers.build(officer_params)
        if @officer.save
          redirect_to partner_portal_law_enforcement_officers_path, notice: "Officer created successfully."
        else
          render :new
        end
      end

      # POST /partner_portal/law_enforcement/officers/:id/revoke
      # Revokes an officer's access — they can no longer log in or submit reports.
      # Used when an officer is suspected of misconduct or corruption.
      def revoke
        return unless enforce_unit_access_on_officer!(@officer)

        if @officer.revoked?
          redirect_to partner_portal_law_enforcement_officers_path,
                      alert: "Cet agent est déjà révoqué."
          return
        end

        reason = params[:reason].presence || "Révoqué par l'administrateur partenaire"

        @officer.update!(status: :revoked)

        AuditLog.create!(
          action:      "officer_revoked",
          record_type: "Officer",
          record_id:   @officer.id,
          officer_id:  @officer.id,
          badge_id:    @officer.badge_id,
          description: {
            officer_email: @officer.email,
            reason:        reason,
            revoked_at:    Time.current.iso8601,
            partner_id:    @partner.id
          }.to_json
        )

        redirect_to partner_portal_law_enforcement_officers_path,
                    notice: "Accès de l'agent #{@officer.full_name} (#{@officer.badge_id}) révoqué avec succès."
      rescue => e
        redirect_to partner_portal_law_enforcement_officers_path,
                    alert: "Échec de la révocation : #{e.message}"
      end

      # POST /partner_portal/law_enforcement/officers/:id/reactivate
      # Re-activates a previously revoked officer.
      def reactivate
        return unless enforce_unit_access_on_officer!(@officer)

        unless @officer.revoked?
          redirect_to partner_portal_law_enforcement_officers_path,
                      alert: "Cet agent n'est pas révoqué."
          return
        end

        @officer.update!(status: :active)

        AuditLog.create!(
          action:      "officer_reactivated",
          record_type: "Officer",
          record_id:   @officer.id,
          officer_id:  @officer.id,
          badge_id:    @officer.badge_id,
          description: {
            officer_email:  @officer.email,
            reactivated_at: Time.current.iso8601,
            partner_id:     @partner.id
          }.to_json
        )

        redirect_to partner_portal_law_enforcement_officers_path,
                    notice: "Accès de l'agent #{@officer.full_name} (#{@officer.badge_id}) rétabli avec succès."
      rescue => e
        redirect_to partner_portal_law_enforcement_officers_path,
                    alert: "Échec de la réactivation : #{e.message}"
      end

      private

      def set_partner
        @partner = @current_partner
      end

      def set_officer
        # Scope to what this admin may see (unit or full partner)
        @officer = apply_portal_officer_scope(@partner.officers).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        redirect_to partner_portal_law_enforcement_officers_path,
                    alert: "Agent introuvable ou accès refusé."
      end

      def officer_params
        params.require(:user).permit(:email, :first_name, :last_name, :unit)
      end
    end
  end
end
