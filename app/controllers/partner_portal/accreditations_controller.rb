# frozen_string_literal: true

module PartnerPortal
  # Partner-portal intake surface for election-day accreditations:
  #   • mandataires (party witnesses)
  #   • national / international observers
  #   • press and international media
  #
  # Partners (parties, observer missions, news organizations) file
  # nominees here; the CEP reviews + activates in the admin namespace.
  # PDF badges are rendered from `#badge` once activated — each badge
  # carries the nominee's name, photo, CIN/BonID, accreditation code,
  # and a color band keyed to the accreditation type.
  class AccreditationsController < PartnerPortal::BaseController
    before_action :set_election
    before_action :require_election!, except: [:index]
    before_action :set_accreditation, only: [:show, :badge, :revoke]

    def index
      if @election
        scope = ElectionAccreditation.where(election: @election)
        scope = scope.where(accreditation_type: params[:type]) if params[:type].present?
        scope = scope.where(status: params[:status])           if params[:status].present?
        if params[:search].present?
          like = "%#{params[:search]}%"
          scope = scope.where(
            "full_name ILIKE ? OR organization ILIKE ? OR accreditation_code ILIKE ?",
            like, like, like
          )
        end

        @stats = {
          total:     ElectionAccreditation.where(election: @election).count,
          active:    ElectionAccreditation.where(election: @election).active.count,
          pending:   ElectionAccreditation.where(election: @election).where(status: "pending").count,
          revoked:   ElectionAccreditation.where(election: @election).where(status: "revoked").count
        }
        @accreditations = scope.order(created_at: :desc).page(params[:page]).per(25)
      else
        @stats = nil
        @accreditations = ElectionAccreditation.none.page(1)
      end
    end

    def show; end

    def new
      @accreditation = ElectionAccreditation.new(
        election: @election,
        organization: current_partner&.name
      )
    end

    def create
      @accreditation = ElectionAccreditation.new(accreditation_params)
      @accreditation.election = @election
      @accreditation.status   = "pending"
      @accreditation.organization = current_partner&.name if @accreditation.organization.blank?

      # Link to a verified BonID user when the supplied BonID resolves.
      if @accreditation.bonid.present? && @accreditation.user.blank?
        matched = User.find_by(bonid: @accreditation.bonid.to_s.strip.upcase)
        if matched&.bonid_verified?
          @accreditation.user = matched
          @accreditation.full_name  ||= matched.full_name
          @accreditation.cin_number ||= matched.id_number if matched.cin?
          @accreditation.identity_verified = true
        end
      end

      if @accreditation.save
        redirect_to partner_portal_accreditation_path(@accreditation),
                    notice: "Akreditasyon depoze. Kòd: #{@accreditation.accreditation_code}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /partner_portal/accreditations/:id/badge
    # Renders the PDF badge for printing. CEP activates the accreditation
    # first (sets status: active + identity_verified: true) — the badge
    # refuses to render for non-active rows so no one distributes an
    # un-reviewed credential.
    def badge
      unless @accreditation.active?
        redirect_to partner_portal_accreditation_path(@accreditation),
                    alert: "Badj la disponib sèlman apre CEP a aktive akreditasyon an."
        return
      end

      pdf_bytes = ::Election::AccreditationBadgePdfService.call(
        accreditation: @accreditation
      )

      send_data pdf_bytes,
                filename: "badj-#{@accreditation.accreditation_code}.pdf",
                type: "application/pdf",
                disposition: "inline"
    end

    # POST /partner_portal/accreditations/:id/revoke
    # Partner-initiated revocation — e.g. the organization is withdrawing a
    # nominee. Final revocation authority still lives with CEP admin, but
    # partners can flag their own people.
    def revoke
      @accreditation.revoke!(reason: params[:reason].presence || "Retire pa òganizasyon an")
      redirect_to partner_portal_accreditation_path(@accreditation),
                  notice: "Akreditasyon revoke."
    end

    private

    def set_election
      @election = BonvoteElection.order(created_at: :desc).first
    end

    def require_election!
      return if @election.present?

      redirect_to partner_portal_accreditations_path,
                  alert: "Pa gen eleksyon aktif."
    end

    def set_accreditation
      @accreditation = ElectionAccreditation.find(params[:id])
    end

    def accreditation_params
      params.require(:election_accreditation).permit(
        :accreditation_type, :bonid, :cin_number, :full_name,
        :organization, :organization_acronym, :department_code,
        :assigned_station_code, :photo_url
      )
    end
  end
end
