# app/controllers/officers/incident_reports_controller.rb
class Officers::IncidentReportsController < Officers::BaseController
  before_action :authenticate_officer!
  before_action :set_incident_report, only: [:show, :edit, :update, :preview, :submit]
  # Access guard: checks IA-only and restricted-unit rules on individual reports
  before_action :check_report_access!, only: [:show, :edit, :update, :preview, :submit]

  def index
    # Scope to what this officer may see based on their unit + rank:
    #   field      → own reports only
    #   supervisor → all reports for their unit within the partner
    #   strategic  → all partner reports
    # JTF override: DCPJ/SWAT officers also see JTF crime types cross-unit.
    @incident_reports = current_officer.effective_incident_reports
                                      .includes(:officer, :address)
                                      .order(created_at: :desc)
  end

  def new
    @incident_report = current_officer.incident_reports.build
    @incident_report.build_address unless @incident_report.address.present?
    @departments = Department.order(:name)

    # Pre-filter crime types based on the officer's unit.
    # Supervisors and strategic officers see all crime types.
    @authorized_crime_types = if current_officer.supervisor_rank? || current_officer.strategic_rank?
      IncidentReport::CRIME_TYPES.values.flatten
    else
      current_officer.authorized_crime_types.presence ||
        IncidentReport::CRIME_TYPES.values.flatten  # fallback if unit has no mapping
    end

    # Handle pre-filling from BonID/BonTouris scan/lookup
    submission = find_submission_from_params

    if submission.is_a?(IdentitySubmission)
      # Pre-build a person involvement with the scanned citizen BonID
      person = @incident_report.person_involvements.build(
        bonid: submission.bonid,
        user_id: submission.user_id,
        name: submission.user&.full_name || submission.full_name,
        role: "suspect" # Default role, officer can change
      )
      person.build_address
      flash.now[:notice] = "BonID verified. Person details pre-filled."
    elsif submission.is_a?(VisitorSubmission)
      # Pre-build a person involvement LINKED to the BonTouris ID
      person = @incident_report.person_involvements.build(
        visitor_submission_id: submission.id,  # Link to BonTouris record
        bonid: submission.bonid,
        first_name: submission.first_name,
        middle_name: submission.middle_name,
        last_name: submission.last_name,
        name: [submission.first_name, submission.last_name].compact.join(" "),
        nationality: submission.nationality,
        date_of_birth: submission.dob,
        sex: submission.sex,
        role: "suspect" # Default role, officer can change
      )
      person.build_address
      flash.now[:notice] = "BonTouris verified. Tourist details pre-filled."
    elsif params[:bonid].present? || params[:bonid_submission_id].present? || params[:visitor_submission_id].present?
      # Params were provided but no valid submission found
      flash.now[:alert] = "Invalid BonID/BonTouris. You may proceed without it."
      @incident_report.person_involvements.build.build_address
    else
      # No BonID params - just build empty person involvement
      @incident_report.person_involvements.build.build_address
    end

    respond_to do |format|
      format.html # normal render
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("incident-report-form", partial: "officers/incident_reports/form", locals: { incident_report: @incident_report })
      end
    end
  end




  def create
    @incident_report = current_officer.incident_reports.build(incident_report_params)
    @incident_report.status = :draft  # Always save as draft first; officer submits via preview

    if @incident_report.save
      # Enqueue watermarking for newly attached evidence photos
      enqueue_watermarking(@incident_report)

      # Log cross-unit crime type mismatch for audit/notification purposes.
      # Field officers are restricted to their unit's crime categories; supervisors/strategic are not.
      unless current_officer.crime_type_authorized?(@incident_report.crime_type)
        log_cross_unit_mismatch(@incident_report)
      end

      if params[:save_as_draft] == "1"
        redirect_to officers_incident_report_path(@incident_report),
                    notice: "💾 Brouillon enregistré. Vous pouvez le modifier et le soumettre plus tard."
      else
        redirect_to preview_officers_incident_report_path(@incident_report),
                    notice: "💾 Brouillon enregistré. Vérifiez les informations avant de signer et soumettre."
      end
    else
      @departments = Department.order(:name)
      @authorized_crime_types = if current_officer.supervisor_rank? || current_officer.strategic_rank?
        IncidentReport::CRIME_TYPES.values.flatten
      else
        current_officer.authorized_crime_types.presence || IncidentReport::CRIME_TYPES.values.flatten
      end
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  # GET /officers/incident_reports/:id/preview
  # Read-only formatted preview of the report with digital signature checkbox.
  # Only accessible for draft and submitted (pending) reports.
  def preview
    unless @incident_report.status_draft? || @incident_report.status_submitted?
      redirect_to officers_incident_report_path(@incident_report),
                  alert: "Ce rapport ne peut plus être modifié avant soumission."
    end
  end

  # POST /officers/incident_reports/:id/submit
  # Officer attests to accuracy and transitions draft → submitted.
  def submit
    unless @incident_report.status_draft?
      redirect_to officers_incident_report_path(@incident_report),
                  alert: "Ce rapport ne peut pas être soumis dans son état actuel." and return
    end

    if @incident_report.update(
      status:              :submitted,
      signed_by_badge_id:  current_officer.badge_id,
      officer_attested_at: Time.current
    )
      assign_supervisor_review(@incident_report)
      notify_emergency_contacts(@incident_report)
      redirect_to officers_incident_report_path(@incident_report),
                  notice: "✅ Rapport signé et soumis. Référence: #{@incident_report.report_id}"
    else
      render :preview, status: :unprocessable_entity
    end
  end

  def edit
    unless @incident_report.officer == current_officer
      redirect_to officers_dashboard_path, alert: "Unauthorized"
    end
  end

  def update
    # Guard against editing locked reports (under review, approved, escalated, archived)
    unless @incident_report.status_draft? || @incident_report.status_submitted? || @incident_report.status_rejected?
      redirect_to officers_incident_report_path(@incident_report),
                  alert: "Ce rapport ne peut plus être modifié." and return
    end

    # Handle media removal on edit (filmstrip X button)
    if params.dig(:incident_report, :remove_media_ids).present?
      ids = Array(params[:incident_report][:remove_media_ids]).map(&:to_i)
      @incident_report.media.where(id: ids).each(&:purge_later)
    end

    if @incident_report.update(incident_report_params)
      # Enqueue watermarking for any newly attached evidence photos
      enqueue_watermarking(@incident_report)

      if @incident_report.status_draft?
        if params[:save_as_draft] == "1"
          redirect_to officers_incident_report_path(@incident_report),
                      notice: "💾 Brouillon mis à jour."
        else
          redirect_to preview_officers_incident_report_path(@incident_report),
                      notice: "💾 Brouillon mis à jour. Vérifiez avant de soumettre."
        end
      else
        redirect_to officers_incident_report_path(@incident_report),
                    notice: "✅ Rapport mis à jour et re-signé."
      end
    else
      # 🔁 Rebuild nested records so errors show in the form
      @incident_report.person_involvements.each { |pi| pi.build_address if pi.address.nil? }

      @departments = Department.order(:name)

      flash.now[:alert] = "Veuillez corriger les erreurs."
      render :edit, status: :unprocessable_entity
    end
  end


  # Lookup user by BonID, respond JSON
  def bonid_lookup
    user = User.find_by(bonid: params[:bonid])

    if user
      render json: {
        name: "#{user.first_name} #{user.middle_name&.first&.upcase}. #{user.last_name}",
        dob: user.dob,
        id_number: user.id_number,
        status: "found"
      }
    else
      render json: { status: "not_found" }, status: :not_found
    end
  end

  private

  # Delegate to the BaseController guard — checks IA-only and restricted-unit rules.
  def check_report_access!
    require_access_to_report!(@incident_report) if @incident_report
  end

  def set_incident_report
    # Scope to `effective_incident_reports` so the officer cannot fetch a UUID
    # that belongs to a report outside their access tier (prevents enumeration AND
    # cross-unit access by guessing UUIDs).
    @incident_report = current_officer.effective_incident_reports
                                      .includes(
                                        :address,
                                        person_involvements: [:user, :visitor_submission, :address],
                                        media_attachments: :blob
                                      )
                                      .find_by!(uuid: params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to officers_incident_reports_path,
                alert: t("incident_reports.not_found", default: "Rapport introuvable ou accès refusé.")
  end

  def incident_report_params
    params.require(:incident_report).permit(
      :crime_type, :crime_level, :occurred_at, :description,
      address_attributes: [ :id, :street_address, :arrondissement_id, :commune_id, :communal_section_id, :department_id, :country, :postal_code, :locality, :plus_code, :latitude, :longitude, :_destroy ],
      person_involvements_attributes: [
        :id, :name, :role, :status, :bonid, :user_id, :visitor_submission_id, :no_bonid, :notify_emergency_contact, :_destroy,
        :first_name, :middle_name, :last_name, :sex, :date_of_birth, :nationality,
        :phone, :email, :cin, :cin_unique_id, :passport_number, :issuing_authority,
        :id_type, :id_issued_on, :id_expires_on,
        :place_of_birth_department_id, :place_of_birth_commune_id,
        address_attributes: [ :id, :street_address, :arrondissement_id, :commune_id, :communal_section_id, :department_id, :country, :postal_code, :locality, :plus_code, :latitude, :longitude, :_destroy ]
      ],
      media: []
    )
  end

  # Enqueue watermarking for each newly attached image that hasn't been watermarked yet.
  # GPS data is passed from the browser via a hidden JSON field (not a model attribute).
  def enqueue_watermarking(report)
    return unless report.media.attached?

    gps_data = begin
      JSON.parse(params.dig(:incident_report, :media_gps) || "[]")
    rescue JSON::ParserError
      []
    end

    report.media.blobs.each_with_index do |blob, index|
      next unless blob.content_type&.start_with?("image/")
      next if blob.metadata&.dig("watermarked")

      gps = gps_data[index] || {}
      WatermarkEvidenceJob.perform_later(
        blob.id,
        current_officer.badge_id,
        gps["lat"],
        gps["lng"],
        gps["timestamp"] || Time.current.iso8601
      )
    end
  rescue StandardError => e
    Rails.logger.error "[IncidentReport] Failed to enqueue watermarking: #{e.message}"
  end

  def notify_emergency_contacts(incident_report)
    incident_report.person_involvements.each do |person|
      next unless person.notify_emergency_contact?
      # Skip if no linked identity (must have either BonID user or BonTouris visitor)
      next unless person.user_id.present? || person.visitor_submission_id.present?

      NotifyEmergencyContactJob.perform_later(person.id)
    end
  end

  def assign_supervisor_review(incident_report)
    supervisor = find_supervisor_for(current_officer)
    return unless supervisor

    IncidentReview.assign(
      incident_report,
      reviewer: supervisor,
      assigned_by: nil,  # System-assigned
      priority: calculate_priority(incident_report),
      deadline: 48.hours.from_now
    )
  rescue => e
    Rails.logger.error "[IncidentReport] Failed to assign supervisor review: #{e.message}"
  end

  def find_supervisor_for(officer)
    # Find an AdminUser who can review reports for this officer's partner
    officer.partner&.admin_user ||
      AdminUser.order(last_sign_in_at: :desc).first
  end

  def calculate_priority(incident_report)
    severity = incident_report.crime_severity_level
    case severity
    when 4..5 then 3  # Critical
    when 3 then 2     # Urgent
    when 2 then 1     # High
    else 0            # Normal
    end
  end

  # Logs a cross-unit crime type mismatch for audit purposes.
  # A field officer filed a crime type outside their unit's expected categories.
  # Phase 2: replace Rails.logger with a background notification job.
  def log_cross_unit_mismatch(report)
    Rails.logger.warn(
      "[AccessControl] Cross-unit crime type: " \
      "officer=#{current_officer.badge_id} unit=#{current_officer.unit_name} " \
      "rank_group=#{current_officer.rank_group} crime_type=#{report.crime_type} " \
      "report_id=#{report.report_id}"
    )
    # Phase 2: CrossUnitMismatchNotifierJob.perform_later(report.id, current_officer.id)
  end

  def find_submission_from_params
    # Try by citizen submission ID first (from QR scan confirmation flow)
    if params[:bonid_submission_id].present?
      return IdentitySubmission.approved.find_by(id: params[:bonid_submission_id])
    end

    # Try by visitor submission ID (from BonTouris scan)
    if params[:visitor_submission_id].present?
      return VisitorSubmission.approved.find_by(id: params[:visitor_submission_id])
    end

    # Try by BonID string (from manual lookup or direct link)
    if params[:bonid].present?
      bonid = params[:bonid].strip.upcase
      # Check if it's a BonTouris format (starts with T-)
      if bonid.start_with?("T-")
        return VisitorSubmission.approved.find_by(bonid: bonid)
      else
        return IdentitySubmission.approved.find_by(bonid: bonid)
      end
    end

    nil
  end
end
