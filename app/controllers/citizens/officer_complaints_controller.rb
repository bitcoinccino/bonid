# app/controllers/citizens/officer_complaints_controller.rb
#
# Citizen-facing controller for filing complaints against PNH officers.
# Automatically pre-populates Pillar 1 fields from the logged-in citizen's BonID
# (or BonTouris if they are a tourist).

module Citizens
  class OfficerComplaintsController < BaseController
    include IdpolExtrasPausable # v1 launch: paused unless IDPOL_EXTRAS_ENABLED=true
    pause_unless_idpol_extras

    before_action :set_complaint, only: [ :show, :certificate ]

    # GET /citizens/officer_complaints
    # List the citizen's own complaints with status
    def index
      @complaints = OfficerComplaint
        .for_citizen(current_citizen.bonid)
        .recent
        .includes(:department, :commune, :accused_officer)
        .page(params[:page]).per(15)
    end

    # GET /citizens/officer_complaints/new
    def new
      @complaint = OfficerComplaint.new
      prefill_complainant_info(@complaint)

      # Pre-populate geo from citizen's home address as a hint
      if current_citizen.address.present?
        @complaint.department_id = current_citizen.address.department_id
        @complaint.commune_id    = current_citizen.address.commune_id
      end

      load_form_data
    end

    # POST /citizens/officer_complaints
    def create
      @complaint = OfficerComplaint.new(complaint_params)
      prefill_complainant_info(@complaint)

      result = IgpnhRoutingService.new(@complaint, filed_by: current_citizen).call

      if result.success?
        @certificate = result.certificate
        redirect_to certificate_citizens_officer_complaint_path(@complaint.uuid),
                    notice: "Plainte soumise avec succès. Référence: #{@complaint.certificate_reference}"
      else
        load_form_data
        flash.now[:alert] = result.errors.join(", ")
        render :new, status: :unprocessable_entity
      end
    end

    # GET /citizens/officer_complaints/fetch_witness?q=XXXXXX
    # Looks up a citizen (BonID) or tourist (BonTouris) by their last 6-8 digits.
    # Returns name, phone, email, photo_url for witness autofill in the complaint form.
    def fetch_witness
      suffix = params[:q].to_s.strip.gsub(/\D/, "") # digits only

      if suffix.length < 6
        return render json: { success: false, error: "Entrez au moins 6 chiffres." }, status: :bad_request
      end

      # 1. Try citizen BonID suffix — matches trailing digits after stripping dashes
      submission = IdentitySubmission
        .approved
        .joins(:user)
        .where("REPLACE(UPPER(identity_submissions.bonid), '-', '') LIKE ?", "%#{suffix.upcase}")
        .order(verified_at: :desc)
        .includes(:user)
        .first

      if submission&.user
        user = submission.user

        # Prevent citizen from citing themselves as witness
        if user.bonid == current_citizen.bonid
          return render json: {
            success: false,
            error: "Vous ne pouvez pas vous citer vous-même comme témoin."
          }, status: :unprocessable_entity
        end

        name = [ user.first_name, user.last_name ].compact_blank.map(&:titleize).join(" ")
        return render json: {
          success:   true,
          id_type:   "citizen",
          bonid:     user.bonid,
          name:      name,
          phone:     user.phone,
          email:     user.email,
          photo_url: user.photo.attached? ? rails_blob_url(user.photo, only_path: true) : nil
        }
      end

      # 2. Try BonTouris suffix — format ends with P-NNNNNN
      visitor = VisitorSubmission
        .where(status: :approved)
        .where("REPLACE(UPPER(bonid), '-', '') LIKE ?", "%#{suffix.upcase}")
        .first

      if visitor
        # Prevent citizen from citing themselves as witness (if citizen is also a tourist)
        if visitor.bonid == current_citizen.bonid
          return render json: {
            success: false,
            error: "Vous ne pouvez pas vous citer vous-même comme témoin."
          }, status: :unprocessable_entity
        end

        name = [ visitor.first_name, visitor.last_name ].compact_blank.map(&:titleize).join(" ")
        return render json: {
          success:   true,
          id_type:   "tourist",
          bonid:     visitor.bonid,
          name:      name,
          phone:     visitor.phone,
          email:     visitor.email,
          photo_url: nil
        }
      end

      render json: {
        success: false,
        error: "Aucun BonID ou BonTouris vérifié trouvé pour ce numéro."
      }, status: :not_found

    rescue => e
      Rails.logger.error("[OfficerComplaintsController] fetch_witness failed: #{e.class} — #{e.message}")
      render json: { success: false, error: "Erreur serveur. Veuillez réessayer." }, status: :internal_server_error
    end

    # GET /citizens/officer_complaints/:uuid
    def show
      @certificate = build_certificate_display(@complaint)
    end

    # GET /citizens/officer_complaints/:uuid/certificate
    def certificate
      @certificate = build_certificate_display(@complaint)
      render :certificate, layout: "printable"
    end

    # GET /citizens/officer_complaints/by_ref/:tracking_number/certificate
    # Backward compatibility: old printed certificates & next-steps links used
    # tracking_number in the URL. Redirect permanently to the UUID-based path.
    def certificate_by_ref
      complaint = OfficerComplaint
        .where(user_id: current_citizen.id)
        .or(OfficerComplaint.where(complainant_bonid: current_citizen.bonid))
        .find_by(tracking_number: params[:tracking_number])

      if complaint
        redirect_to certificate_citizens_officer_complaint_path(complaint.uuid),
                    status: :moved_permanently
      else
        redirect_to citizens_officer_complaints_path,
                    alert: "Plainte introuvable ou accès refusé."
      end
    end

    private

    # Lookup by UUID (2^122 — unguessable) scoped to current citizen.
    # If a guessed UUID belongs to another citizen, find_by! returns nil →
    # RecordNotFound → redirect. No information leakage about other complaints.
    def set_complaint
      @complaint = OfficerComplaint
        .where(user_id: current_citizen.id)
        .or(OfficerComplaint.where(complainant_bonid: current_citizen.bonid))
        .find_by!(uuid: params[:uuid])
    rescue ActiveRecord::RecordNotFound
      redirect_to citizens_officer_complaints_path,
                  alert: "Plainte introuvable ou accès refusé." and return
    end

    def prefill_complainant_info(complaint)
      complaint.user_id            = current_citizen.id
      complaint.complainant_type   = "citizen"
      complaint.complainant_bonid  = current_citizen.bonid
      complaint.complainant_name   ||= current_citizen.full_name
      complaint.complainant_cin    ||= current_citizen.id_type == "cin" ? current_citizen.id_number : nil
      complaint.complainant_phone  ||= current_citizen.phone
      complaint.complainant_email  ||= current_citizen.email
    end

    def complaint_params
      params.require(:officer_complaint).permit(
        # Pillar 1 — Complainant (editable overrides)
        :complainant_name, :complainant_phone, :complainant_email,
        :complainant_role,

        # Pillar 2 — Incident Details
        :occurred_at, :location_description,
        :pnh_unit_involved, :department_id, :arrondissement_id, :commune_id, :communal_section_id,
        :street_address, :locality, :postal_code, :country,

        # Pillar 3 — Officer Identification
        :accused_officer_badge, :accused_officer_name,
        :accused_officer_vehicle, :accused_officer_unit,
        :physical_description,

        # Pillar 4 — Allegations
        :allegation_category, :specific_allegation,

        # Pillar 5 — Evidence & Narrative
        :narrative,
        witnesses: [ :name, :phone, :email, :bonid, :relation, :id_type ],
        evidences: []
      )
    end

    def load_form_data
      @departments       = Department.order(:name)
      @arrondissements   = @complaint.department_id.present? ?
                             Arrondissement.where(department_id: @complaint.department_id).order(:name) :
                             Arrondissement.none
      @communes          = @complaint.arrondissement_id.present? ?
                             Commune.where(arrondissement_id: @complaint.arrondissement_id).order(:name) :
                             Commune.none
      @communal_sections = @complaint.commune_id.present? ?
                             CommunalSection.where(commune_id: @complaint.commune_id).order(:name) :
                             CommunalSection.none
      @allegation_types  = OfficerConstants::COMPLAINT_TYPES
      @pnh_units         = OfficerConstants::UNIT_OPTIONS.keys
      @roles             = OfficerComplaint.complainant_roles.keys
    end

    def build_certificate_display(complaint)
      {
        certificate_reference:   complaint.certificate_reference,
        tracking_number:         complaint.tracking_number,
        submitted_at:            complaint.submitted_at,
        status:                  complaint.status,
        status_label:            complaint.status_label,
        status_color:            complaint.status_color,
        complainant_name:        complaint.complainant_name,
        complainant_bonid:       complaint.complainant_bonid,
        allegation_category:     complaint.allegation_category,
        specific_allegation:     complaint.specific_allegation,
        occurred_at:             complaint.occurred_at,
        department:              complaint.department&.name,
        commune:                 complaint.commune&.name,
        routed_directorate_name: complaint.routing_directorate_name,
        routed_directorate_code: complaint.routed_directorate,
        # Anti-tamper fields
        certificate_checksum:    complaint.certificate_checksum,
        certificate_signed_at:   complaint.certificate_signed_at,
        certificate_valid:       complaint.certificate_valid?,
        verification_url:        complaint.verification_url,
        qr_png_base64:           complaint.certificate_qr_png_base64,
        next_steps: [
          "Conservez votre numéro de référence: #{complaint.certificate_reference}",
          "Un enquêteur de l'IGPNH vous contactera dans 5 à 10 jours ouvrables.",
          "Vérifiez votre statut sur bonid.ht/citizens/officer_complaints/#{complaint.uuid}",
          "Si aucune réponse sous 15 jours, présentez ce certificat à l'OPC."
        ]
      }
    end
  end
end
