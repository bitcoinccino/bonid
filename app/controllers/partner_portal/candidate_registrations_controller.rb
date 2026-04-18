# frozen_string_literal: true

module PartnerPortal
  class CandidateRegistrationsController < PartnerPortal::BaseController
    before_action :set_election
    before_action :require_election!, except: [ :index ]
    before_action :ensure_candidate_registration_phase!, only: [ :new, :create ]
    before_action :set_candidate, only: [ :show, :new_dispute, :create_dispute ]

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

      # Attach verified BonID user, if the submitted bonid resolves to one.
      # Without this, `populate_from_bonid!` would be dead code because the
      # form never captures user_id directly.
      if @candidate.user.blank? && @candidate.bonid.present?
        matched = User.find_by(bonid: @candidate.bonid.to_s.strip.upcase)
        @candidate.user = matched if matched&.bonid_verified?
      end

      # Auto-fill from BonID user profile (only fills fields that are blank)
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

    # Approval authority for candidate nominations lives with the CEP, not
    # with party operators — see Election::Admin::CandidatesController. The
    # partner portal is submit-and-track only: parties file the dossier, then
    # monitor its review status here. (Previous approve/reject/start_review
    # actions were removed on 2026-04-17 as a separation-of-powers fix.)

    # GET /partner_portal/candidate_registrations/:id/new_dispute
    # Filing surface for a rejected candidacy — the only due-process path
    # today. Challenges route to BCEN (Election::Admin::DisputesController).
    def new_dispute
      unless @candidate.registration_status == "rejected"
        redirect_to partner_portal_candidate_registration_path(@candidate),
                    alert: "Kontestasyon disponib sèlman pou kandidati ki rejte."
        return
      end
      @dispute = ElectionDispute.new(prefill_dispute_from_candidate)
    end

    # POST /partner_portal/candidate_registrations/:id/create_dispute
    def create_dispute
      unless @candidate.registration_status == "rejected"
        redirect_to partner_portal_candidate_registration_path(@candidate),
                    alert: "Kontestasyon disponib sèlman pou kandidati ki rejte."
        return
      end

      @dispute = ElectionDispute.new(prefill_dispute_from_candidate.merge(dispute_params))
      @dispute.election = @election

      if @dispute.save
        redirect_to partner_portal_candidate_registration_path(@candidate),
                    notice: "Kontestasyon soumèt. Referans: #{@dispute.reference_code}. BCEN gen 5 jou pou reponn."
      else
        render :new_dispute, status: :unprocessable_entity
      end
    end

    # GET /partner_portal/candidate_registrations/lookup_bonid?bonid=BON-XXXX
    # JSON endpoint used by the wizard's "Pre-ranpli ak BonID" button to
    # pre-fill identity / residence fields on Step 1. Only responds with data
    # when the BonID resolves to a user whose identity was approved.
    def lookup_bonid
      code = params[:bonid].to_s.strip.upcase
      user = code.present? ? User.find_by(bonid: code) : nil

      unless user&.bonid_verified?
        render json: { found: false } and return
      end

      render json: {
        found: true,
        fields: {
          full_name:            user.full_name,
          cin_number:           (user.cin? ? user.id_number : nil),
          date_of_birth:        user.dob&.iso8601,
          sex:                  (user.sex == "male" ? "M" : (user.sex == "female" ? "F" : nil)),
          marital_status:       user.marital_status,
          place_of_birth:       [ user.birth_commune&.name, user.birth_department&.name ].compact.join(", ").presence || user.place_of_birth,
          nationality:          user.nationality || "haitian",
          residence_department: user.address&.department&.name,
          residence_commune:    user.address&.commune&.name,
          residence_address:    user.address&.street_address,
          department_code:      user.address&.department&.id&.to_s
        }.compact
      }
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
      candidate.place_of_birth ||= [ user.birth_commune&.name, user.birth_department&.name ].compact.join(", ").presence || user.place_of_birth
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
      nif_record = user.verification_records.where.not(nif: [ nil, "" ]).first
      candidate.profession ||= nif_record&.owner_role_custom

      # DGI tax compliance check — has the citizen filed taxes?
      latest_dgi = user.dgi_payments.successful.order(paid_at: :desc).first
      if latest_dgi
        candidate.doc_dgi_receipt ||= true
        candidate.dgi_receipt_number ||= latest_dgi.order_id
      end
    end

    def dispute_params
      params.require(:election_dispute).permit(
        :subject, :description, :evidence_summary, :priority
      )
    end

    # Pre-populate a dispute with context from the rejected candidacy so the
    # filer doesn't retype identity info. Merged with user-supplied params.
    def prefill_dispute_from_candidate
      {
        dispute_type:           "challenge",
        filed_by_type:          "candidate",
        filed_by_name:          @candidate.full_name,
        filed_by_bonid:         @candidate.bonid,
        filed_by_organization:  @candidate.party_name,
        constituency_id:        @candidate.election_constituency_id,
        department_code:        @candidate.department_code,
        commune_id:             @candidate.commune_id,
        priority:               "normal",
        subject:                "Kontestasyon rejet kandidati ##{@candidate.recepisse_number}"
      }
    end

    def generate_recepisse(candidate)
      prefix = candidate.position&.first&.upcase || "X"
      year = Time.current.year
      random = SecureRandom.hex(4).upcase
      "REC-#{year}-#{prefix}-#{random}"
    end
  end
end
