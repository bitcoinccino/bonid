# frozen_string_literal: true

module Citizens
  class IdentitySubmissionsController < BaseController
    layout "citizen"
    include ActionView::RecordIdentifier

    before_action :authenticate_citizen!
    skip_before_action :authenticate_citizen!, only: [ :verify, :verified_profile ]
    skip_before_action :require_citizen!, only: [ :verify, :verified_profile ]
    before_action :set_partner, only: %i[new create request_new]
    before_action :set_submission, only: %i[show edit update refresh_qr]
    before_action :ensure_profile_complete!, only: %i[new create update]
    before_action :authorize_submission_edit, only: :edit




    # ------------------------------------------------------------
    # GET /citizens/identity_submissions
    # Redirect to dashboard - submission status is shown there
    # ------------------------------------------------------------
    def index
      redirect_to citizens_dashboard_path
    end

    # ------------------------------------------------------------
    # GET /citizens/identity_submissions/new
    # Handles initial, resubmission, and reissue flows
    # ------------------------------------------------------------
    def new
      @suppress_submission_alert = true

      # Guard: don't show upload form if citizen already has an approved BonID
      if current_citizen.identity_submissions.exists?(status: :approved) &&
         params[:resubmission_from].blank?
        redirect_to citizens_dashboard_path,
                    notice: "You already have a verified BonID."
        return
      end

      if params[:resubmission_from].present?
        previous = current_citizen.identity_submissions.find_by(public_token: params[:resubmission_from])

        if previous&.status_rejected? || previous&.status_revoked?
          sub_type = previous.status_revoked? ? :reissue : :resubmission
          @identity_submission = current_citizen.identity_submissions.build(
            submission_type: sub_type,
            partner_id: previous.partner_id,
            id_type: previous.id_type,
            status: :pending,
            reason: previous.reason,
            other_reason: previous.other_reason
          )

          # Smart Resubmission: skip liveness + signature if previous data is reusable
          detect_reusable_biometrics!(previous)
          detect_reusable_signature!(previous)

          flash[:info] = if previous.status_revoked?
                           "Please upload your updated ID documents for the name change."
                         elsif @skip_liveness && @skip_signature
                           "Your face verification and signature from your previous submission are still valid. Just upload corrected documents."
                         elsif @skip_liveness
                           "Your face verification from your previous submission is still valid. Just upload corrected documents."
                         else
                           "Resubmission pre-filled from your previous attempt. Update as needed."
                         end
        else
          redirect_to citizens_dashboard_path, alert: "⚠️ Invalid resubmission request."
          nil
        end
      else
        last = current_citizen.identity_submissions.order(created_at: :desc).first
        resolved_type = case last&.status
        when "rejected" then "resubmission"
        when "approved" then "reissue"
        else "initial"
        end

        # Pre-fill country of residence from waitlist signup (so citizen
        # doesn't answer the same question twice)
        waitlist = WaitlistSignup.find_by(email: current_citizen.email)
        prefill_country = waitlist&.country_of_residence.presence ||
                          current_citizen.address&.country.presence || "HT"

        @identity_submission = current_citizen.identity_submissions.build(
          submission_type: resolved_type,
          partner: @partner,
          id_type: current_citizen.id_type,
          document_number: current_citizen.id_number,
          country_of_residence: prefill_country
        )

        # Smart Resubmission: skip liveness + signature if last submission's data is reusable
        if last&.status_rejected?
          detect_reusable_biometrics!(last)
          detect_reusable_signature!(last)
        end
      end
    end

    #  Move this OUTSIDE new
    def verified_profile
      @submission = IdentitySubmission.find_by!(public_token: params[:public_token])

      unless @submission.status_approved?
        render plain: "This BonID has not been verified.", status: :forbidden
        return
      end

      if @submission.expires_at.present? && @submission.expires_at < Time.current
        render plain: "This BonID has expired.", status: :forbidden
        return
      end

      @partner_name =
        params[:partner].present? ?
          Partner.find_by(slug: params[:partner])&.name :
          nil

      render "citizens/identity_submissions/verified_profile", layout: "public"
    end


    # ------------------------------------------------------------
    # GET /citizens/identity_submissions/:id/edit
    # Edit existing submission (e.g., pending/rejected)
    # ------------------------------------------------------------
    def edit
      @suppress_submission_alert = true
      # @submission set by before_action; delegation handles personal fields
    end

    # ------------------------------------------------------------
    # POST /citizens/identity_submissions
    # ------------------------------------------------------------
    def create
      @identity_submission = current_citizen.identity_submissions.build(identity_submission_params.except("first_name", "middle_name", "last_name", "dob", "sex", "marital_status"))  # Ignore personal (sync to user if needed)
      @identity_submission.partner_id ||= @partner&.id
      @identity_submission.user = current_citizen
      @identity_submission.status = :pending
      @identity_submission.submission_type ||= :initial
      @suppress_submission_alert = true

      # Auto-fill document details from citizen profile when the form hides those fields
      # (profile_has_doc = true means the document_details section was not rendered)
      if @identity_submission.document_number.blank? && current_citizen.id_number.present?
        @identity_submission.document_number = current_citizen.id_number
      end
      if @identity_submission.document_issue_date.blank? && current_citizen.id_issued_on.present?
        @identity_submission.document_issue_date = current_citizen.id_issued_on
      end
      if @identity_submission.document_expiry_date.blank? && current_citizen.id_expires_on.present?
        @identity_submission.document_expiry_date = current_citizen.id_expires_on
      end

      # Optional: Sync personal to user on create
      personal_params = identity_submission_params.slice("first_name", "middle_name", "last_name", "dob", "sex", "marital_status")
      current_citizen.update!(personal_params) if personal_params.values.any?(&:present?)

      # Sync document number & dates to user record
      if @identity_submission.document_number.present?
        doc_attrs = {
          id_number: @identity_submission.document_number,
          id_expires_on: @identity_submission.document_expiry_date,
          id_issued_on: @identity_submission.document_issue_date
        }
        # If 10-digit NINU, also store in the dedicated ninu field
        if CinNumberValidator.generation(@identity_submission.document_number) == :ninu
          doc_attrs[:ninu] = @identity_submission.document_number
        end
        current_citizen.update!(doc_attrs)
      end

      # Log IP geolocation for diaspora verification (don't block, admin reviews)
      if @identity_submission.country_of_residence.present?
        ip_country = begin
          Geocoder.search(request.remote_ip).first&.country_code
        rescue => e
          Rails.logger.warn("[Geolocation] Failed: #{e.message}")
          nil
        end
        geo_meta = @identity_submission.metadata || {}
        geo_meta["geo"] = {
          "ip" => request.remote_ip,
          "country_from_ip" => ip_country,
          "country_selected" => @identity_submission.country_of_residence,
          "match" => (ip_country.to_s.upcase == @identity_submission.country_of_residence.to_s.upcase)
        }
        @identity_submission.metadata = geo_meta
      end

      ActiveRecord::Base.transaction do
        # ── Smart Resubmission: carry forward signature from previous submission ──
        if params[:skip_signature] == "true" && params[:previous_signature_signed_id].present?
          carry_forward_signature!(@identity_submission)
        else
          attach_signature!(@identity_submission)
          attach_drawn_signature!(@identity_submission)
        end

        # ── Smart Resubmission: carry forward biometrics from previous submission ──
        skip_liveness_active = params[:skip_liveness] == "true" && params[:previous_selfie_signed_id].present?
        if skip_liveness_active
          carry_forward_biometrics!(@identity_submission)
        end

        # Store liveness metadata if liveness check was performed (normal flow)
        # Skip if biometrics were carried forward — session may have stale data
        if session[:liveness_metadata].present? && !skip_liveness_active
          liveness_data = session[:liveness_metadata].dup

          # Pick up backgrounded audit blob IDs from Rails.cache (uploaded by AuditBlobUploadJob)
          if liveness_data["audit_pending_session_id"].present?
            pending_sid = liveness_data.delete("audit_pending_session_id")
            cached_blob_ids = Rails.cache.read("audit_blob_ids:#{pending_sid}")
            if cached_blob_ids.present?
              liveness_data["audit_blob_ids"] = cached_blob_ids
              Rails.cache.delete("audit_blob_ids:#{pending_sid}")
            end
          end

          # Attach audit images to submission (prevents ActiveStorage orphan purge)
          if liveness_data["audit_blob_ids"].present?
            audit_blobs = ActiveStorage::Blob.where(id: liveness_data["audit_blob_ids"])
            audit_blobs.each { |blob| @identity_submission.liveness_audit_images.attach(blob) }
            liveness_data.delete("audit_blob_ids")  # Clean up — blobs are now attached
          end

          @identity_submission.metadata = (@identity_submission.metadata || {}).merge(
            "liveness" => liveness_data
          )
        end

        if @identity_submission.save
          Citizens::IdentitySubmissionMailer.submission_received_email(@identity_submission).deliver_later
          session.delete(:bonid_partner_id)
          session.delete(:liveness_session_id)
          session.delete(:liveness_created_at)
          session.delete(:liveness_blob_signed_id)
          session.delete(:liveness_metadata)
          session.delete(:liveness_audit_signed_ids)  # legacy cleanup

          # Trigger async face matching (selfie vs ID document)
          FaceMatchJob.perform_later(@identity_submission.id)

          # Trigger async OCR on CIN/Passport for cross-check
          DocumentOcrJob.perform_later(@identity_submission.id)

          redirect_to citizens_dashboard_path,
                      notice: "✅ Verification submitted successfully. A confirmation email has been sent to your inbox."
        else
          flash.now[:alert] = @identity_submission.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
          raise ActiveRecord::Rollback
        end
      end
    rescue => e
      Rails.logger.error "❌ [IdentitySubmission#create] Failed: #{e.class} - #{e.message}"
      flash.now[:alert] = "⚠️ Something went wrong. Please recheck your signature or uploaded files."
      render :new, status: :unprocessable_entity
    end

    # ------------------------------------------------------------
    # GET /citizens/identity_submissions/:public_token
    # ------------------------------------------------------------
    def show
      @submissions = current_citizen.identity_submissions.order(created_at: :desc)
      @last_submission = @submissions.first
    end

    # ------------------------------------------------------------
    # PATCH/PUT /citizens/identity_submissions/:public_token
    # ------------------------------------------------------------
    def update
      @suppress_submission_alert = true
      @submission.status = :pending

      attach_signature!(@submission)
      attach_drawn_signature!(@submission)

      # Update only submission fields; personal via delegation
      update_attrs = identity_submission_params.except("first_name", "middle_name", "last_name", "dob", "sex", "marital_status")
      @submission.assign_attributes(update_attrs)

      # Sync personal to user if changed
      personal_params = identity_submission_params.slice("first_name", "middle_name", "last_name", "dob", "sex", "marital_status")
      current_citizen.update!(personal_params) if personal_params.values.any?(&:present?)

      if @submission.save
        Citizens::IdentitySubmissionMailer.submission_updated_email(@submission).deliver_later if update_attrs.present?

        # Re-run face matching if selfie or ID documents were updated
        if update_attrs.keys.any? { |k| k.in?(%w[selfie cin_front cin_back passport]) }
          current_meta = @submission.metadata || {}
          @submission.update_column(:metadata, current_meta.except("face_match"))
          FaceMatchJob.perform_later(@submission.id)
        end

        redirect_to citizens_identity_submission_path(@submission),
                    notice: "✅ Your submission was updated successfully."
      else
        flash.now[:alert] = @submission.errors.full_messages.to_sentence.presence || "⚠️ Failed to update submission."
        render :new, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "❌ [IdentitySubmission#update] Failed: #{e.class} - #{e.message}"
      flash.now[:alert] = "⚠️ Invalid signature or missing attachments."
      render :new, status: :unprocessable_entity
    end

    # ------------------------------------------------------------
    # POST /citizens/identity_submissions/request_new
    # ------------------------------------------------------------
    def request_new
      reason = params[:reason].to_s
      unless reason.in?(%w[name_change expired])
        return redirect_to citizens_dashboard_path, alert: "Invalid reason for request."
      end

      previous = current_citizen.identity_submissions
                                .where(status: %i[approved revoked])
                                .order(verified_at: :desc).first

      partner_id = previous&.partner_id || @partner&.id
      return redirect_back fallback_location: citizens_dashboard_path,
                           alert: "Missing partner information." if partner_id.blank?

      # Name change → citizen must re-upload updated ID documents via full form
      if reason == "name_change"
        previous&.update!(status: :revoked)
        redirect_to new_citizens_identity_submission_path(resubmission_from: previous&.public_token),
                    notice: "Please re-submit your updated ID documents for the name change."
        return
      end

      # Expired → fast-track reissue (no new documents needed)
      previous&.update!(status: :revoked)

      new_submission = current_citizen.identity_submissions.build(
        submission_type: :reissue,
        status: :pending,
        reason: reason,
        id_type: current_citizen.id_type.presence || "cin",
        partner_id: partner_id,
        skip_document_validations: true
      )
      new_submission.build_address(current_citizen.address.attributes) if current_citizen.address

      if new_submission.save
        redirect_to citizens_dashboard_path, notice: "New BonID request submitted successfully."
      else
        redirect_to citizens_dashboard_path, alert: new_submission.errors.full_messages.to_sentence
      end
    end

# ------------------------------------------------------------
# POST /citizens/identity_submissions/:id/refresh_qr
# ------------------------------------------------------------
# ------------------------------------------------------------
# POST /citizens/identity_submissions/:public_token/refresh_qr
# ------------------------------------------------------------
def refresh_qr
  @submission = current_citizen
                  .identity_submissions
                  .approved
                  .find_by(public_token: params[:public_token])

  if @submission.nil?
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = "No active BonID found."
        render turbo_stream: turbo_stream.prepend(
          "flash_messages",
          partial: "shared/flash"
        )
      end

      format.html do
        redirect_to citizens_dashboard_path,
                    alert: "No active BonID found."
      end
    end
    return
  end

  # -------------------------------------------------------------
  # Detect auto-refresh (modal open or rotator interval)
  # -------------------------------------------------------------
  @auto_refresh = params[:auto] == "true"

  # Rotate / regenerate QR
  @submission.rotate_qr_for_citizen!

  respond_to do |format|
    format.turbo_stream  # @auto_refresh is used in the template
    format.html do
      redirect_to citizens_dashboard_path,
                  notice: "BonID QR Code refreshed successfully."
    end
  end
end



def verify
  token = params[:token].to_s
  submission = IdentitySubmission.find_by(verification_token: token)

  unless submission&.status_approved?
    render plain: "⚠️ Invalid or expired BonID QR code.", status: :not_found
    return
  end

  # ------------------------------------------------------------
  # Detect verified partner (if any)
  # ------------------------------------------------------------
  partner_name = nil

  partner_slug =
    params[:partner].presence ||
    request.referrer&.match(%r{/partners/([\w-]+)})&.captures&.first

  if partner_slug.present?
    partner = Partner.where(slug: partner_slug).where.not(verified_at: nil).first
    partner_name = partner&.name
  end

  # ------------------------------------------------------------
  # Log QR scan (non-blocking)
  # ------------------------------------------------------------
  begin
    submission.qr_scan_logs.create!(
      scanned_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      referrer: request.referrer,
      partner_name: partner_name
    )
  rescue => e
    Rails.logger.warn("⚠️ QR scan log failed for token #{token}: #{e.message}")
  end

  # ------------------------------------------------------------
  # Redirect to PUBLIC verified profile
  # ------------------------------------------------------------
  redirect_to verified_profile_citizens_identity_submission_path(
    submission.public_token,
    partner: partner_slug
  )
rescue => e
  Rails.logger.error "❌ QR verify error: #{e.class} - #{e.message}"
  render plain: "Internal error verifying BonID.", status: :internal_server_error
end

    # ------------------------------------------------------------
    # GET /citizens/identity_submissions/scan_history
    # ------------------------------------------------------------
    def scan_history
      @submissions = current_citizen.identity_submissions
                                    .includes(:qr_scan_logs)
                                    .order(created_at: :desc)
                                    .page(params[:page]).per(10)
    end

    def support_faq; end

    # ------------------------------------------------------------
    # POST /citizens/identity_submissions/liveness_session
    # Creates an AWS Rekognition Face Liveness session
    # ------------------------------------------------------------
    def liveness_session
      # Server-side rate limiting: 5 attempts per 3 minutes
      if FaceLivenessService.rate_limited?(current_citizen.id)
        render json: { error: "Too many attempts. Please wait a few minutes before trying again." }, status: :too_many_requests
        return
      end

      # Idempotency: return cached session if one exists for this user.
      # Prevents duplicate AWS sessions from React re-renders, double-clicks,
      # or network retries — critical at 100k+ user scale.
      # Cache TTL is 2 minutes — AWS sessions expire quickly, and returning
      # a stale session causes "Session expired or interrupted" errors.
      cache_key = "liveness_session:#{current_citizen.id}"

      # If client explicitly requests a fresh session (retry), clear cache
      if params[:force_new].present?
        Rails.cache.delete(cache_key)
      end

      cached_session_id = Rails.cache.read(cache_key)

      if cached_session_id
        session[:liveness_session_id] = cached_session_id
        session[:liveness_created_at] = Time.current.to_i
        Rails.logger.info "[LivenessSession] Returning cached session: #{cached_session_id}"
        render json: { session_id: cached_session_id }
        return
      end

      result = FaceLivenessService.create_session

      if result[:success]
        Rails.cache.write(cache_key, result[:session_id], expires_in: 2.minutes)
        session[:liveness_session_id] = result[:session_id]
        session[:liveness_created_at] = Time.current.to_i
        render json: { session_id: result[:session_id] }
      else
        Rails.logger.error "[LivenessSession] Failed: #{result[:error]}"
        render json: { error: result[:error] || "Failed to create liveness session" }, status: :service_unavailable
      end
    end

    # ------------------------------------------------------------
    # GET /citizens/identity_submissions/liveness_results
    # Triggers async retrieval of Face Liveness results.
    # Returns immediately with { status: "processing" } — the
    # frontend polls /liveness_status for the final result.
    # This eliminates the synchronous AWS API call that blocks
    # the user for 2–10s on Haiti's slow mobile networks.
    # ------------------------------------------------------------
    def liveness_results
      sid = params[:session_id]

      unless session[:liveness_session_id] == sid
        render json: { error: "Invalid session" }, status: :forbidden and return
      end

      # AWS sessions expire after 3 minutes
      if Time.current.to_i - session[:liveness_created_at].to_i > 180
        render json: { error: "Session expired" }, status: :gone and return
      end

      # Enqueue background job — returns immediately
      LivenessResultJob.perform_later(sid, current_citizen.id)

      render json: { status: "processing", session_id: sid }
    end

    # ------------------------------------------------------------
    # GET /citizens/identity_submissions/liveness_status
    # Polling endpoint: returns cached results once LivenessResultJob
    # has completed, or { status: "processing" } if still running.
    # Frontend polls every 2s, max 15 attempts (30s timeout).
    # ------------------------------------------------------------
    def liveness_status
      sid = params[:session_id]

      unless session[:liveness_session_id] == sid
        render json: { error: "Invalid session" }, status: :forbidden and return
      end

      cached = Rails.cache.read("liveness_result:#{sid}")

      unless cached
        render json: { status: "processing" } and return
      end

      if cached[:status] == "completed" && cached[:passed]
        # Store metadata in session (same flow as the old sync path)
        session[:liveness_blob_signed_id] = cached[:blob_signed_id]
        session[:liveness_metadata] = {
          "session_id" => sid,
          "status" => cached[:result_status],
          "confidence" => cached[:confidence],
          "passed" => true,
          "needs_review" => cached[:needs_review] || false,
          "checked_at" => Time.current.iso8601
        }

        if cached[:needs_review]
          session[:liveness_metadata]["audit_pending_session_id"] = sid
        end

        # Clean up caches
        Rails.cache.delete("liveness_result:#{sid}")
        Rails.cache.delete("liveness_session:#{current_citizen.id}")

        render json: {
          status: "completed",
          passed: true,
          confidence: cached[:confidence],
          needs_review: cached[:needs_review] || false,
          blob_signed_id: cached[:blob_signed_id],
          session_id: sid
        }
      elsif cached[:status] == "completed"
        Rails.cache.delete("liveness_result:#{sid}")

        render json: {
          status: "completed",
          passed: false,
          confidence: cached[:confidence]
        }
      else
        Rails.cache.delete("liveness_result:#{sid}")

        render json: { status: "error", error: cached[:error] }, status: :service_unavailable
      end
    end

    # ------------------------------------------------------------
    # POST /citizens/identity_submissions/manual_selfie
    # Low-bandwidth fallback: accepts a static selfie when the
    # live face check fails due to network timeouts.
    # Flags submission as needs_manual_review so admins know
    # liveness was bypassed. FaceMatchJob still compares against
    # the ID photo after submission.
    # ------------------------------------------------------------
    def manual_selfie
      unless params[:selfie].present?
        render json: { error: "No selfie provided." }, status: :unprocessable_entity and return
      end

      blob = ActiveStorage::Blob.create_and_upload!(
        io: params[:selfie].tempfile,
        filename: "manual_selfie_#{current_citizen.id}_#{Time.current.to_i}.jpg",
        content_type: params[:selfie].content_type
      )

      session[:liveness_blob_signed_id] = blob.signed_id
      session[:liveness_metadata] = {
        "session_id" => "manual_#{SecureRandom.hex(8)}",
        "status" => "MANUAL_SELFIE",
        "confidence" => 0,
        "passed" => true,
        "needs_review" => true,
        "manual_selfie" => true,
        "low_bandwidth_mode" => true,
        "checked_at" => Time.current.iso8601
      }

      # Clear idempotency cache so retry creates a fresh session
      Rails.cache.delete("liveness_session:#{current_citizen.id}")

      render json: { blob_signed_id: blob.signed_id, manual_selfie: true }
    rescue => e
      Rails.logger.error "[ManualSelfie] Upload failed: #{e.class} - #{e.message}"
      render json: { error: "Upload failed. Please try again." }, status: :service_unavailable
    end

    # ------------------------------------------------------------
    # POST /citizens/identity_submissions/face_compare
    # Compares liveness selfie against uploaded ID photo in real-time
    # during Step 2, BEFORE the citizen can proceed to Step 3.
    # ------------------------------------------------------------
    def face_compare
      selfie_signed_id = params[:selfie_blob_signed_id] || session[:liveness_blob_signed_id]
      id_photo = params[:id_photo]

      unless selfie_signed_id.present?
        render json: { error: "No selfie found. Please complete the liveness check first." }, status: :unprocessable_entity and return
      end

      unless id_photo.present?
        render json: { error: "No ID photo provided." }, status: :unprocessable_entity and return
      end

      # Resolve selfie blob from signed ID
      selfie_blob = ActiveStorage::Blob.find_signed(selfie_signed_id)
      unless selfie_blob
        render json: { error: "Selfie image not found." }, status: :unprocessable_entity and return
      end

      # Download both images (with ghost file resilience for selfie blob)
      selfie_bytes = download_blob_safely(selfie_blob)
      id_photo_bytes = id_photo.read

      unless selfie_bytes.present? && id_photo_bytes.present?
        render json: { error: "Failed to read images." }, status: :unprocessable_entity and return
      end

      # Call AWS Rekognition compare_faces
      begin
        client = FaceMatchService.rekognition_client
        response = client.compare_faces(
          source_image: { bytes: selfie_bytes },
          target_image: { bytes: id_photo_bytes },
          similarity_threshold: 0
        )

        source_confidence = response.source_image_face&.confidence&.round(2)
        Rails.logger.info "[FaceCompare] Source face confidence: #{source_confidence}%"

        if response.face_matches.any?
          best = response.face_matches.max_by(&:similarity)
          similarity = best.similarity.round(2)
          target_confidence = best.face&.confidence&.round(2)
          Rails.logger.info "[FaceCompare] Result: similarity=#{similarity}%, target_confidence=#{target_confidence}%, threshold=#{FaceMatchService::SIMILARITY_THRESHOLD}%"

          if similarity >= FaceMatchService::SIMILARITY_THRESHOLD
            render json: { match: true, similarity: similarity }
          else
            Rails.logger.warn "[FaceCompare] MISMATCH: #{similarity}% < #{FaceMatchService::SIMILARITY_THRESHOLD}% threshold"
            render json: { match: false, similarity: similarity, message: "Your face does not match the ID photo (#{similarity}% similarity). Please upload a valid ID document with your photo." }
          end
        elsif response.unmatched_faces.any?
          Rails.logger.warn "[FaceCompare] No match found, unmatched faces detected"
          render json: { match: false, similarity: 0, message: "Your face does not match the face on the ID document." }
        else
          Rails.logger.warn "[FaceCompare] No face detected on target document"
          render json: { match: false, similarity: 0, message: "No human face detected on the ID document. Please upload a clear photo of your ID." }
        end
      rescue Aws::Rekognition::Errors::InvalidParameterException => e
        # ALL InvalidParameterException from compare_faces means the image
        # doesn't contain a valid/detectable human face (e.g., animal photo,
        # blank image, scenery, etc.). Always block — never fall back.
        Rails.logger.warn "[FaceCompare] InvalidParameterException (blocking): #{e.message}"
        render json: { match: false, similarity: 0, message: "No valid face detected on the ID document. Please upload a clear photo of your ID with your face visible." }
      rescue StandardError => e
        Rails.logger.error "[FaceCompare] Error: #{e.class} - #{e.message}"
        render json: { error: "Face comparison temporarily unavailable." }, status: :service_unavailable
      end
    end

    private

    # ------------------------------------------------------------
    # Smart Resubmission Helpers
    # ------------------------------------------------------------

    # Sets @skip_liveness and @previous_selfie_signed_id if the previous
    # submission's biometrics can be carried forward.
    # Strictly tied to current_citizen (User ID) to prevent cross-user leaks.
    def detect_reusable_biometrics!(previous_submission)
      return unless previous_submission&.biometrics_reusable?

      @skip_liveness = true
      @previous_selfie_signed_id = previous_submission.selfie.blob.signed_id
      @previous_liveness_metadata = previous_submission.metadata["liveness"]
      @previous_face_match = previous_submission.metadata["face_match"]
      Rails.logger.info "[SmartResubmission] User ##{current_citizen.id}: biometrics reusable from submission ##{previous_submission.id}"
    end

    # Carries forward liveness metadata + selfie from a previous submission.
    # Re-validates that the selfie blob actually belongs to the current user's
    # previous submission (prevents parameter tampering).
    def carry_forward_biometrics!(new_submission)
      previous_sub = current_citizen.identity_submissions.rejected
        .where("metadata->'liveness' IS NOT NULL")
        .order(created_at: :desc).first

      return unless previous_sub&.biometrics_reusable?
      return unless previous_sub.selfie.blob.signed_id == params[:previous_selfie_signed_id]

      # Carry forward liveness metadata with audit trail
      carried_liveness = previous_sub.metadata["liveness"].merge(
        "reused_from_submission_id" => previous_sub.id,
        "reused_from_submission_uuid" => previous_sub.uuid,
        "reused_at" => Time.current.iso8601
      )

      new_submission.metadata = (new_submission.metadata || {}).merge(
        "liveness" => carried_liveness
      )

      Rails.logger.info "[SmartResubmission] User ##{current_citizen.id}: carried forward biometrics from submission ##{previous_sub.id} to new submission"
    end

    # Sets @skip_signature and @previous_signature_signed_id if the previous
    # submission's signature can be carried forward.
    def detect_reusable_signature!(previous_submission)
      return unless previous_submission&.signature_reusable?

      @skip_signature = true
      @previous_signature_signed_id = previous_submission.signature.blob.signed_id
      Rails.logger.info "[SmartResubmission] User ##{current_citizen.id}: signature reusable from submission ##{previous_submission.id}"
    end

    # Carries forward the signature blob from a previous submission.
    # Re-validates ownership to prevent parameter tampering.
    def carry_forward_signature!(new_submission)
      previous_sub = current_citizen.identity_submissions.rejected
        .order(created_at: :desc)
        .detect(&:signature_reusable?)

      return unless previous_sub
      return unless previous_sub.signature.blob.signed_id == params[:previous_signature_signed_id]

      # Attach the same blob to the new submission
      new_submission.signature.attach(previous_sub.signature.blob)
      Rails.logger.info "[SmartResubmission] User ##{current_citizen.id}: carried forward signature from submission ##{previous_sub.id}"
    end

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------
    def set_partner
      if session[:bonid_partner_id].present?
        @partner = Partner.find_by(id: session[:bonid_partner_id])
        redirect_to(partners_path, alert: "⚠️ Partner not verified.") and return unless @partner&.verified_at.present?
      else
        @partner = Partner.find_by(slug: "bonid-central")
        unless @partner
          valid_sector = Partner::SECTORS.values.flatten.first || "banking"
          @partner = Partner.create!(
            name: "BonID Central",
            slug: "bonid-central",
            sector: valid_sector,
            verified_at: Time.current,
            api_key_digest: SecureRandom.hex(32)
          )
        end
      end
    end

    def set_submission
      @submission = current_citizen.identity_submissions.find_by(public_token: params[:public_token])

      unless @submission
        Rails.logger.warn(
          "⚠️ [set_submission] Submission NOT found for user=#{current_citizen.id}, public_token=#{params[:public_token]}"
        )
        redirect_to citizens_dashboard_path, alert: "⚠️ Submission not found."
      end
    end

    # Authorize edits (e.g., only pending/rejected)
    def authorize_submission_edit
      unless @submission.status_pending? || @submission.status_rejected?
        redirect_to citizens_identity_submission_path(@submission), alert: "⚠️ This submission cannot be edited."
      end
    end

    # Params: Exclude personal (handled via delegation/user update)
    def identity_submission_params
      params.require(:identity_submission).permit(
        :id_type, :submission_type, :partner_id, :reason, :other_reason,
        :first_name, :middle_name, :last_name, :dob, :sex, :marital_status,  # Allowed for user sync
        :cin_front, :cin_back, :passport,
        :document_number, :document_expiry_date, :document_issue_date,        # CIN/Passport number & dates
        :country_of_residence, :host_country_id_type, :host_country_id,        # Diaspora fields
        :diaspora_proof_type, :diaspora_proof_of_address,                     # Diaspora proof of address
        :selfie, :proof_of_address, :signature, :signature_drawn,
        :additional_proof, :additional_proof_type,
        address_attributes: [ :id, :street, :city, :state, :postal_code, :country ]
      )
    end

    def ensure_profile_complete!
      unless current_citizen&.profile_complete?
        redirect_to edit_citizens_profile_path,
                    alert: "To submit your identity for verification, please complete your profile first."
      end
    end

    def attach_signature!(submission)
      return unless params[:identity_submission][:signature].present?
      submission.signature.attach(params[:identity_submission][:signature])
    rescue => e
      Rails.logger.error "⚠️ [attach_signature!] Failed: #{e.message}"
    end

    def attach_drawn_signature!(submission)
      drawn = params[:identity_submission][:signature_drawn]
      return unless drawn.present? && drawn.start_with?("data:image")

      decoded = Base64.decode64(drawn.split(",").last)
      submission.signature.attach(
        io: StringIO.new(decoded),
        filename: "signature.png",
        content_type: "image/png"
      )
    rescue => e
      Rails.logger.error "⚠️ [attach_drawn_signature!] Failed: #{e.message}"
    end

    # Downloads blob bytes with resilience against ghost files (blob in DB, file missing from disk).
    # Mirrors the fallback pattern from FaceMatchService#download_blob.
    def download_blob_safely(blob)
      blob.download
    rescue ActiveStorage::FileNotFoundError, Errno::ENOENT => e
      Rails.logger.warn "[FaceCompare] Blob file missing (#{blob.filename}), trying URL fallback: #{e.message}"
      download_blob_via_url(blob)
    rescue StandardError => e
      Rails.logger.warn "[FaceCompare] Direct download error for blob ##{blob.id}: #{e.class} - #{e.message}. Trying URL fallback..."
      download_blob_via_url(blob)
    end

    def download_blob_via_url(blob)
      url = blob.url(expires_in: 60.seconds)
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        Rails.logger.info "[FaceCompare] URL fallback succeeded for blob ##{blob.id} (#{response.body.bytesize} bytes)"
        response.body
      else
        Rails.logger.error "[FaceCompare] URL fallback failed for blob ##{blob.id}: HTTP #{response.code}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "[FaceCompare] URL fallback error for blob ##{blob.id}: #{e.class} - #{e.message}"
      nil
    end
  end
end
