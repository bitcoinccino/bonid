# frozen_string_literal: true

module PartnerPortal
  class CandidateRegistrationsController < PartnerPortal::BaseController
    before_action :set_election
    before_action :require_election!, except: [:index]
    before_action :ensure_candidate_registration_phase!, only: [:new, :create]
    before_action :set_candidate, only: [:show, :approve, :reject, :start_review]

    def index
      if @election
        scope = ElectionCandidate.where(election: @election)
        scope = scope.where(registration_status: params[:status]) if params[:status].present?
        scope = scope.where(position: params[:position]) if params[:position].present?
        scope = scope.where("full_name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

        @stats = ElectionCandidate.registration_stats_for(@election)
        @candidates = scope.order(created_at: :desc).page(params[:page]).per(25)
      else
        @stats = nil
        @candidates = ElectionCandidate.none.page(1)
      end
    end

    def show; end

    def new
      @candidate = ElectionCandidate.new(election: @election)
      @candidate.party_registration_id = params[:party_registration_id] if params[:party_registration_id]
      @constituencies = @election.election_constituencies.order(:position, :constituency_name)
      @approved_parties = ElectionPartyRegistration.where(election: @election).approved.order(:party_name)
    end

    def create
      @candidate = ElectionCandidate.new(candidate_params)
      @candidate.election = @election
      @candidate.registration_status = "submitted"
      @candidate.submitted_at = Time.current
      @candidate.status = "active"

      # Auto-fill from BonID user profile
      populate_from_bonid!(@candidate) if @candidate.user.present?

      # Auto-fill from party registration
      if @candidate.party_registration.present?
        @candidate.party_name = @candidate.party_registration.party_name
        @candidate.party_acronym = @candidate.party_registration.party_acronym
        @candidate.candidacy_type = @candidate.party_registration.registration_type
      end

      # Calculate registration fee
      @candidate.registration_fee_gourdes = @candidate.calculate_fee
      @candidate.recepisse_number = generate_recepisse(@candidate)

      if @candidate.save
        redirect_to partner_portal_candidate_registration_path(@candidate), notice: "Kandida soumèt avèk siksè."
      else
        @constituencies = @election.election_constituencies.order(:position, :constituency_name)
        @approved_parties = ElectionPartyRegistration.where(election: @election).approved.order(:party_name)
        render :new, status: :unprocessable_entity
      end
    end

    def approve
      if @candidate.approve!(admin: current_admin_user)
        redirect_to partner_portal_candidate_registrations_path, notice: "#{@candidate.full_name} apwouve."
      else
        redirect_to partner_portal_candidate_registration_path(@candidate), alert: "Erè pandan apwobasyon."
      end
    end

    def reject
      reason = params[:rejection_reason].to_s.strip
      if reason.blank?
        redirect_to partner_portal_candidate_registration_path(@candidate), alert: "Rezon rejeksyon obligatwa."
        return
      end

      if @candidate.reject!(admin: current_admin_user, reason: reason)
        redirect_to partner_portal_candidate_registrations_path, notice: "#{@candidate.full_name} rejte."
      else
        redirect_to partner_portal_candidate_registration_path(@candidate), alert: "Erè pandan rejeksyon."
      end
    end

    def start_review
      @candidate.start_review!
      redirect_to partner_portal_candidate_registration_path(@candidate), notice: "Revizyon kòmanse."
    end

    private

    def set_election
      @election = BonvoteElection.order(created_at: :desc).first
    end

    def require_election!
      return if @election.present?

      redirect_to partner_portal_candidate_registrations_path,
                  alert: "Pa gen eleksyon aktif. Kreye yon eleksyon anvan."
    end

    def set_candidate
      @candidate = ElectionCandidate.find(params[:id])
    end

    def ensure_candidate_registration_phase!
      phase = ElectoralCalendar.current_phase(@election)
      return if phase&.phase == "candidate_registration"

      # Find the actual candidate registration phase for date info
      reg_phase = @election&.electoral_calendars&.find_by(phase: "candidate_registration")

      if reg_phase
        redirect_to partner_portal_candidate_registrations_path,
                    alert: "Enskripsyon kandida poko louvri. Dat ofisyèl: #{reg_phase.start_date.strftime('%d %B %Y')} — #{reg_phase.end_date.strftime('%d %B %Y')}."
      else
        redirect_to partner_portal_candidate_registrations_path,
                    alert: "Enskripsyon kandida fèmen. Kalandriye elektoral la poko jenere."
      end
    end

    def candidate_params
      params.require(:election_candidate).permit(
        :full_name, :position, :party_name, :party_acronym,
        :department_code, :commune_id, :election_constituency_id,
        :platform_statement, :user_id, :bonid, :cin_number, :photo_url,
        :party_registration_id, :candidacy_type, :date_of_birth, :place_of_birth,
        :sex, :marital_status, :profession, :nationality,
        :residence_department, :residence_commune, :residence_address,
        :fee_reduced, :fee_reduction_reason,
        :doc_birth_certificate, :doc_cin_oni, :doc_casier_judiciaire,
        :doc_dgi_receipt, :doc_property_proof, :doc_residence_attestation,
        :doc_immigration_cert, :doc_discharge, :doc_passport_photos,
        :doc_party_mandate, :doc_support_petition, :doc_profession_proof
      )
    end

    # Auto-populate candidate fields from BonID user profile
    # BonID links to: identity (ONI/CIN), address, DGI (tax), photos
    def populate_from_bonid!(candidate)
      user = candidate.user
      candidate.bonid          ||= user.bonid
      candidate.full_name      ||= user.full_name
      candidate.cin_number     ||= user.id_number if user.cin?
      candidate.date_of_birth  ||= user.dob
      candidate.place_of_birth ||= [user.birth_commune&.name, user.birth_department&.name].compact.join(", ").presence || user.place_of_birth
      candidate.sex            ||= user.sex == "male" ? "M" : (user.sex == "female" ? "F" : nil)
      candidate.marital_status ||= user.marital_status
      candidate.nationality    ||= user.nationality || "haitian"
      candidate.photo_url      ||= (Rails.application.routes.url_helpers.url_for(user.photo) if user.photo&.attached?) rescue nil

      # Address → residence + department
      if user.address.present?
        candidate.residence_department ||= user.address.department&.name
        candidate.residence_commune    ||= user.address.commune&.name
        candidate.residence_address    ||= user.address.street_address
        candidate.department_code      ||= user.address.department&.id&.to_s
        candidate.doc_residence_attestation = true if user.address.street_address.present?
      end

      # BonID verified → CIN/ONI document auto-checked
      candidate.doc_cin_oni = true if user.bonid_verified?

      # BonID photo → passport photos auto-checked
      candidate.doc_passport_photos = true if user.photo&.attached?

      # DGI link → tax receipt + NIF verification
      # Check if candidate has paid election registration fee via DGI
      election_payment = user.dgi_payments
                             .where(form_type: "election_registration", status: "completed")
                             .order(paid_at: :desc).first
      if election_payment
        candidate.doc_dgi_receipt = true
        candidate.fee_paid = true
        candidate.dgi_receipt_number = election_payment.order_id
      end

      # NIF from verification records
      nif_record = user.verification_records.where.not(nif: [nil, ""]).first
      candidate.profession ||= nif_record&.owner_role_custom

      # DGI tax compliance check — has the citizen filed taxes?
      latest_dgi = user.dgi_payments.successful.order(paid_at: :desc).first
      if latest_dgi
        candidate.doc_dgi_receipt ||= true
        candidate.dgi_receipt_number ||= latest_dgi.order_id
      end
    end

    def generate_recepisse(candidate)
      prefix = candidate.position&.first&.upcase || "X"
      year = Time.current.year
      random = SecureRandom.hex(4).upcase
      "REC-#{year}-#{prefix}-#{random}"
    end
  end
end
