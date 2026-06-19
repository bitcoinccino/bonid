# frozen_string_literal: true

module Public
  class VisitorsController < Visitors::VisitorBaseController
    include BontourisPausable # v1 launch: paused unless BONTOURIS_ENABLED=true
    pause_bontouris_unless_enabled

    skip_before_action :authenticate_citizen!, raise: false
    layout :resolve_layout

    # ============================================================
    # BEFORE ACTIONS (ORDER MATTERS)
    # ============================================================
    before_action :set_visitor, only: %i[
      verify_email
      resend_otp
      documents
      documents_submit
      success
      reapply
      download_pdf
    ]

    # 🔐 Everything AFTER OTP requires a valid access grant
    before_action :require_access_grant!, only: %i[
      documents
      documents_submit
      success
      download_pdf
    ]

    before_action :disable_cache!, only: %i[
      verify_email
      documents
      success
      download_pdf
    ]

    # ============================================================
    # STEP 0 — LANDING
    # ============================================================
    def get_started; end

    # ============================================================
    # STEP 1 — NEW APPLICATION
    # ============================================================
    def new
      @visitor_submission = VisitorSubmission.new
      @visitor_submission.build_address(country: "Haiti")
      @visitor_submission.build_local_contact
    end

    def create
      @visitor_submission = VisitorSubmission.new(visitor_params)
      @visitor_submission.status = :pending_email_verification

      # Merge liveness metadata from session (biometric verification)
      if session[:liveness_metadata].present?
        @visitor_submission.liveness_metadata = session[:liveness_metadata]
      end

      if @visitor_submission.save
        # Clean up liveness session data
        session.delete(:liveness_session_id)
        session.delete(:liveness_created_at)
        session.delete(:liveness_blob_signed_id)
        session.delete(:liveness_metadata)

        issue_otp!(@visitor_submission)
        flash[:otp_notice] = t("bon_touris.notices.otp_sent")

        redirect_to verify_email_public_visitor_path(@visitor_submission.public_id)
      else
        @visitor_submission.build_address(country: "Haiti") unless @visitor_submission.address
        @visitor_submission.build_local_contact unless @visitor_submission.local_contact
        render :new, status: :unprocessable_entity
      end
    end

    # ============================================================
    # PASSPORT OCR — AWS Textract
    # ============================================================
    def scan_passport
      unless params[:passport_image].present?
        return render json: { success: false, error: "No image provided" }, status: :unprocessable_entity
      end

      image_bytes = params[:passport_image].read
      result = PassportOcrService.call(image_bytes)
      render json: result
    end

    # ============================================================
    # FACE LIVENESS — AWS Rekognition (visitor biometric flow)
    # ============================================================
    def liveness_session
      visitor_key = request.session.id

      if FaceLivenessService.rate_limited?(visitor_key)
        render json: { error: "Too many attempts. Please wait before trying again." }, status: :too_many_requests
        return
      end

      # Idempotency: return cached session if one exists
      cache_key = "liveness_session:visitor:#{visitor_key}"
      cached_session_id = Rails.cache.read(cache_key)

      if cached_session_id
        session[:liveness_session_id] = cached_session_id
        session[:liveness_created_at] = Time.current.to_i
        render json: { session_id: cached_session_id }
        return
      end

      result = FaceLivenessService.create_session

      if result[:success]
        Rails.cache.write(cache_key, result[:session_id], expires_in: 5.minutes)
        session[:liveness_session_id] = result[:session_id]
        session[:liveness_created_at] = Time.current.to_i
        render json: { session_id: result[:session_id] }
      else
        render json: { error: result[:error] }, status: :service_unavailable
      end
    end

    def liveness_results
      sid = params[:session_id]

      unless session[:liveness_session_id] == sid
        render json: { error: "Invalid session" }, status: :forbidden
        return
      end

      # AWS liveness sessions expire after 3 minutes
      if Time.current.to_i - session[:liveness_created_at].to_i > 180
        render json: { error: "Session expired" }, status: :gone
        return
      end

      # Enqueue background job — returns immediately
      LivenessResultJob.perform_later(sid, request.session.id)
      render json: { status: "processing", session_id: sid }
    end

    def liveness_status
      sid = params[:session_id]

      unless session[:liveness_session_id] == sid
        render json: { error: "Invalid session" }, status: :forbidden
        return
      end

      cached = Rails.cache.read("liveness_result:#{sid}")

      unless cached
        render json: { status: "processing" }
        return
      end

      if cached[:status] == "completed" && cached[:passed]
        # Store metadata in session for form submission
        session[:liveness_blob_signed_id] = cached[:blob_signed_id]
        session[:liveness_metadata] = {
          "session_id" => sid,
          "status" => cached[:result_status],
          "confidence" => cached[:confidence],
          "passed" => true,
          "needs_review" => cached[:needs_review] || false,
          "checked_at" => Time.current.iso8601
        }

        # Clean up caches
        Rails.cache.delete("liveness_result:#{sid}")
        Rails.cache.delete("liveness_session:visitor:#{request.session.id}")

        render json: {
          status: "completed",
          passed: true,
          confidence: cached[:confidence],
          needs_review: cached[:needs_review] || false,
          blob_signed_id: cached[:blob_signed_id]
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

    def face_compare
      selfie_signed_id = params[:selfie_blob_signed_id] || session[:liveness_blob_signed_id]
      id_photo = params[:id_photo]

      unless selfie_signed_id.present?
        render json: { error: "No selfie found. Please complete the face verification first." }, status: :unprocessable_entity
        return
      end

      unless id_photo.present?
        render json: { error: "No passport photo provided." }, status: :unprocessable_entity
        return
      end

      # Resolve selfie blob from signed ID
      selfie_blob = ActiveStorage::Blob.find_signed(selfie_signed_id)
      unless selfie_blob
        render json: { error: "Selfie image not found." }, status: :unprocessable_entity
        return
      end

      # Download both images
      selfie_bytes = download_blob_safely(selfie_blob)
      id_photo_bytes = id_photo.read

      unless selfie_bytes.present? && id_photo_bytes.present?
        render json: { error: "Failed to read images." }, status: :unprocessable_entity
        return
      end

      # Call AWS Rekognition compare_faces
      begin
        client = FaceMatchService.rekognition_client
        response = client.compare_faces(
          source_image: { bytes: selfie_bytes },
          target_image: { bytes: id_photo_bytes },
          similarity_threshold: 0
        )

        if response.face_matches.any?
          best = response.face_matches.max_by(&:similarity)
          similarity = best.similarity.round(2)

          if similarity >= FaceMatchService::SIMILARITY_THRESHOLD
            render json: { match: true, similarity: similarity }
          else
            render json: {
              match: false,
              similarity: similarity,
              message: "Your face does not match the passport photo (#{similarity}% similarity)."
            }
          end
        elsif response.unmatched_faces.any?
          render json: { match: false, similarity: 0, message: "Your face does not match the face on the passport." }
        else
          render json: { match: false, similarity: 0, message: "No human face detected on the passport photo." }
        end
      rescue Aws::Rekognition::Errors::InvalidParameterException
        render json: { match: false, similarity: 0, message: "No valid face detected on the passport photo." }
      rescue StandardError => e
        Rails.logger.error "[VisitorsController#face_compare] Error: #{e.class} - #{e.message}"
        render json: { error: "Face comparison temporarily unavailable." }, status: :service_unavailable
      end
    end

    def manual_selfie
      unless params[:selfie].present?
        render json: { error: "No image provided" }, status: :unprocessable_entity
        return
      end

      blob = ActiveStorage::Blob.create_and_upload!(
        io: params[:selfie].tempfile,
        filename: "manual_selfie_visitor_#{Time.current.to_i}.jpg",
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

      Rails.cache.delete("liveness_session:visitor:#{request.session.id}")

      render json: { blob_signed_id: blob.signed_id, manual_selfie: true }
    end

    # ============================================================
    # STEP 2 — EMAIL OTP VERIFICATION
    # ============================================================
    def verify_email
      # GET — show OTP form
      if request.get?
        if @visitor.email_otp_sent_at.blank? || @visitor.email_otp_sent_at < 10.minutes.ago
          redirect_to get_started_public_visitors_path,
                      alert: t("bon_touris.alerts.otp_required")
          return
        end
        return
      end

      # POST — verify OTP
      unless @visitor.email_otp_valid?(params[:otp])
        flash.now[:alert] = t("bon_touris.alerts.invalid_or_expired_code")
        render :verify_email, status: :unprocessable_entity
        return
      end

      @visitor.mark_email_verified!

      grant = VisitorAccessGrant.issue!(
        visitor_submission: @visitor,
        ttl: 2.hours
      )

      if @visitor.documents_required?
        redirect_to documents_public_visitor_path(
          @visitor.public_id,
          access_token: grant.token
        ),
        status: :see_other
      else
        redirect_to success_public_visitor_path(
          @visitor.public_id,
          access_token: grant.token
        ),
        status: :see_other
      end
    end

    def resend_otp
      issue_otp!(@visitor)
      flash[:otp_notice] = t("bon_touris.notices.otp_resent")

      redirect_to verify_email_public_visitor_path(@visitor.public_id)
    end

    # ============================================================
    # STEP 3 — DOCUMENT UPLOAD
    # ============================================================
    def documents
      unless @visitor.email_verified?
        redirect_to get_started_public_visitors_path,
                    alert: t("bon_touris.alerts.session_expired")
        return
      end

      unless @visitor.documents_required?
        redirect_to success_public_visitor_path(
          @visitor.public_id,
          access_token: params[:access_token]
        )
      end
    end

    def documents_submit
      unless @visitor.documents_required?
        redirect_to success_public_visitor_path(
          @visitor.public_id,
          access_token: params[:access_token]
        )
        return
      end

      if @visitor.update(visitor_submission_params)
        # 🚨 Guarantee selfie_captured_at
        if @visitor.selfie.attached? && @visitor.selfie_captured_at.blank?
          @visitor.update_column(:selfie_captured_at, Time.current)
        end

        @visitor.submit_documents!
        VisitorMailer.with(visitor: @visitor).documents_received.deliver_later

        redirect_to success_public_visitor_path(
          @visitor.public_id,
          access_token: params[:access_token]
        ),
        status: :see_other
      else
        render :documents, status: :unprocessable_entity
      end
    end

    # ============================================================
    # STEP 4 — STATUS PAGE (TERMINAL)
    # ============================================================
    def success
      # set_visitor already loaded @visitor
      @visitor_submission = @visitor
      @view_mode = "certificate"
    end

    # ============================================================
    # DOWNLOAD CERTIFICATE PDF (APPROVED ONLY)
    # ============================================================
    def download_pdf
      unless @visitor.approved?
        redirect_to get_started_public_visitors_path,
                    alert: t("bon_touris.alerts.session_expired")
        return
      end

      pdf = VisitorPdfGenerator.new(@visitor).generate

      send_data pdf,
                filename: "BonTouris_ID_#{@visitor.bonid}.pdf",
                type: "application/pdf",
                disposition: "inline"
    end

    # ============================================================
    # REAPPLY — RESET A REJECTED APPLICATION
    # ============================================================
    def reapply
      visitor = VisitorSubmission.find_by!(public_id: params[:id])

      unless visitor.rejected?
        redirect_to get_started_public_visitors_path,
                    alert: t("bon_touris.alerts.application_not_found")
        return
      end

      VisitorSubmission.transaction do
        visitor.update!(
          status: :pending_email_verification,
          email_verified_at: nil,
          email_otp: nil,
          email_otp_sent_at: nil,
          rejection_reason: nil,
          rejection_notes: nil,
          rejected_at: nil,
          rejected_by_admin_id: nil
        )

        visitor.selfie.purge if visitor.selfie.attached?
        visitor.passport_photo.purge if visitor.passport_photo.attached?
      end

      issue_otp!(visitor)

      redirect_to verify_email_public_visitor_path(visitor.public_id),
                  notice: t("bon_touris.notices.otp_sent")
    end

    # ============================================================
    # RESUME APPLICATION FROM EMAIL
    # ============================================================
    def continue
      email = params[:email].to_s.strip.downcase

      return redirect_with_error(
        t("bon_touris.alerts.email_required")
      ) if email.blank?

      visitor = VisitorSubmission.resume_for_email(email)

      return redirect_with_error(
        t("bon_touris.alerts.email_not_found")
      ) unless visitor

      issue_otp!(visitor)
      flash[:otp_notice] = t("bon_touris.notices.otp_sent")

      redirect_to verify_email_public_visitor_path(visitor.public_id)
    end

    # ============================================================
    # PRIVATE
    # ============================================================
    private

    def set_visitor
      @visitor =
        VisitorSubmission.find_by(public_id: params[:id]) ||
        VisitorSubmission.find_by(id: params[:id])

      return if @visitor

      redirect_to get_started_public_visitors_path,
                  alert: t("bon_touris.alerts.application_not_found")
      nil
    end

    def require_access_grant!
      token = params[:access_token].to_s

      grant = VisitorAccessGrant.find_by(
        token: token,
        visitor_submission_id: @visitor.id
      )

      unless grant&.valid_for_use?
        redirect_to get_started_public_visitors_path,
                    alert: t("bon_touris.alerts.session_expired")
        nil
      end
    end

    def issue_otp!(visitor)
      return if visitor.email_otp_sent_at&.>(2.minutes.ago)

      visitor.generate_email_otp!
      VisitorMailer.with(visitor: visitor).email_verification.deliver_later
    end

    def resolve_layout
      case action_name
      when "download_pdf"
        "pdf"
      when "scan_passport", "liveness_session", "liveness_results", "liveness_status", "face_compare", "manual_selfie"
        false # JSON responses, no layout
      when "success", "get_started", "new", "create", "documents", "documents_submit"
        "visitor"
      else
        "visitor_auth"
      end
    end

    def download_blob_safely(blob)
      blob.download
    rescue ActiveStorage::FileNotFoundError, Errno::ENOENT => e
      Rails.logger.warn "[VisitorsController] Direct download failed for blob ##{blob.id}: #{e.message}. Trying URL fallback..."
      begin
        uri = URI.parse(blob.url(expires_in: 5.minutes))
        response = Net::HTTP.get_response(uri)
        response.is_a?(Net::HTTPSuccess) ? response.body : nil
      rescue StandardError => url_err
        Rails.logger.error "[VisitorsController] URL fallback failed: #{url_err.message}"
        nil
      end
    end

    def visitor_params
      params.require(:visitor_submission).permit(
        :title, :first_name, :middle_name, :last_name, :dob, :sex,
        :nationality, :residence_country, :email, :phone,
        :passport_number, :passport_expiry_date,
        :purpose_of_visit, :stay_duration_days, :entry_mode,
        :transport_provider, :transport_reference,
        :port_of_entry, :accommodation_name, :accommodation_type,
        address_attributes: %i[
          street_address department_id arrondissement_id
          commune_id communal_section_id postal_code country
        ],
        local_contact_attributes: %i[
          name phone phone_country_code email relationship verified user_id
        ]
      )
    end

    def visitor_submission_params
      params.require(:visitor_submission).permit(
        :selfie,
        :passport_photo,
        :affirm_information,
        :selfie_captured_at
      )
    end

    def disable_cache!
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
      response.headers["Pragma"]        = "no-cache"
      response.headers["Expires"]       = "0"
    end

    def redirect_with_error(message)
      redirect_to get_started_public_visitors_path, alert: message
    end
  end
end

# # frozen_string_literal: true

# module Public
#   class VisitorsController < Visitors::VisitorBaseController
#     skip_before_action :authenticate_citizen!, raise: false
#     layout :resolve_layout

#     # ============================================================
#     # BEFORE ACTIONS (ORDER MATTERS)
#     # ============================================================
#     before_action :set_visitor, only: %i[
#       verify_email
#       resend_otp
#       documents
#       documents_submit
#       success
#       reapply
#       download_pdf
#     ]

#     # 🔐 Everything AFTER OTP requires a valid access grant
#     before_action :require_access_grant!, only: %i[
#       documents
#       documents_submit
#       success
#       download_pdf
#     ]

#     before_action :disable_cache!, only: %i[
#       verify_email
#       documents
#       success
#       download_pdf
#     ]

#     # # Consume the one-time access grant only on the final success page
#     # after_action :consume_access_grant!, only: :success

#     # ============================================================
#     # STEP 0 — LANDING
#     # ============================================================
#     def get_started; end

#     # ============================================================
#     # STEP 1 — NEW APPLICATION
#     # ============================================================
#     def new
#       @visitor_submission = VisitorSubmission.new
#       @visitor_submission.build_address(country: "Haiti")
#       @visitor_submission.build_local_contact
#     end

#     def create
#       @visitor_submission = VisitorSubmission.new(visitor_params)
#       @visitor_submission.status = :pending_email_verification

#       if @visitor_submission.save
#         issue_otp!(@visitor_submission)
#         flash[:otp_notice] = t("bon_touris.notices.otp_sent")

#         redirect_to verify_email_public_visitor_path(@visitor_submission.public_id)
#       else
#         render :new, status: :unprocessable_entity
#       end
#     end

#     # ============================================================
#     # STEP 2 — EMAIL OTP VERIFICATION
#     # ============================================================
#     def verify_email
#       # GET — show OTP form
#       if request.get?
#         if @visitor.email_otp_sent_at.blank? || @visitor.email_otp_sent_at < 10.minutes.ago
#           redirect_to get_started_public_visitors_path,
#                       alert: t("bon_touris.alerts.otp_required")
#           return
#         end
#         return
#       end

#       # POST — verify OTP
#       unless @visitor.email_otp_valid?(params[:otp])
#         flash.now[:alert] = t("bon_touris.alerts.invalid_or_expired_code")
#         render :verify_email, status: :unprocessable_entity
#         return
#       end

#       @visitor.mark_email_verified!

#       grant = VisitorAccessGrant.issue!(
#         visitor_submission: @visitor,
#         ttl: 2.hours
#       )

#       if @visitor.documents_required?
#         redirect_to documents_public_visitor_path(
#           @visitor.public_id,
#           access_token: grant.token
#         ),
#         status: :see_other
#       else
#         redirect_to success_public_visitor_path(
#           @visitor.public_id,
#           access_token: grant.token
#         ),
#         status: :see_other
#       end
#     end

#     def resend_otp
#       issue_otp!(@visitor)
#       flash[:otp_notice] = t("bon_touris.notices.otp_resent")

#       redirect_to verify_email_public_visitor_path(@visitor.public_id)
#     end

#     # ============================================================
#     # STEP 3 — DOCUMENT UPLOAD
#     # ============================================================
#     def documents
#       unless @visitor.email_verified?
#         redirect_to get_started_public_visitors_path,
#                     alert: t("bon_touris.alerts.session_expired")
#         return
#       end

#       unless @visitor.documents_required?
#         redirect_to success_public_visitor_path(
#           @visitor.public_id,
#           access_token: params[:access_token]
#         )
#       end
#     end

#     def documents_submit
#       unless @visitor.documents_required?
#         redirect_to success_public_visitor_path(
#           @visitor.public_id,
#           access_token: params[:access_token]
#         )
#         return
#       end

#       if @visitor.update(visitor_submission_params)
#         # 🚨 Guarantee selfie_captured_at
#         if @visitor.selfie.attached? && @visitor.selfie_captured_at.blank?
#           @visitor.update_column(:selfie_captured_at, Time.current)
#         end

#         @visitor.submit_documents!
#         VisitorMailer.with(visitor: @visitor).documents_received.deliver_later

#         redirect_to success_public_visitor_path(
#           @visitor.public_id,
#           access_token: params[:access_token]
#         ),
#         status: :see_other
#       else
#         render :documents, status: :unprocessable_entity
#       end
#     end

# # ============================================================
# # STEP 4 — STATUS PAGE (TERMINAL)
# # ============================================================
# def success
#   # Find submission
#   @visitor_submission = VisitorSubmission.find_by(public_id: params[:id])

#   # Find and validate access grant
#   @access_grant = VisitorAccessGrant.find_by(
#     token: params[:access_token],
#     visitor_submission_id: @visitor_submission.id
#   )

#   # If no grant or already consumed → redirect
#   if @access_grant.nil? || @access_grant.consumed?
#     redirect_to get_started_public_visitors_path,
#                 alert: t("bon_touris.alerts.link_expired_or_invalid")
#     return
#   end

#   # CONSUME TOKEN NOW — before rendering
#   @access_grant.consume!

#   # ALWAYS show the status page — regardless of approval
#   # Your view already handles approved / pending / rejected beautifully
#   @visitor = @visitor_submission
#   @view_mode = "certificate"
# end

#     # ============================================================
#     # DOWNLOAD CERTIFICATE PDF (APPROVED ONLY)
#     # ============================================================
#     def download_pdf
#       require_access_grant!

#       unless @visitor.approved?
#         redirect_to get_started_public_visitors_path,
#                     alert: t("bon_touris.alerts.session_expired")
#         return
#       end

#       pdf = VisitorPdfGenerator.new(@visitor).generate

#       send_data pdf,
#                 filename: "BonTouris_ID_#{@visitor.bonid}.pdf",
#                 type: "application/pdf",
#                 disposition: "inline"
#     end

#     # ============================================================
#     # REAPPLY — RESET A REJECTED APPLICATION
#     # ============================================================
#     def reapply
#       visitor = VisitorSubmission.find_by!(public_id: params[:id])

#       unless visitor.rejected?
#         redirect_to get_started_public_visitors_path,
#                     alert: t("bon_touris.alerts.application_not_found")
#         return
#       end

#       VisitorSubmission.transaction do
#         visitor.update!(
#           status: :pending_email_verification,
#           email_verified_at: nil,
#           email_otp: nil,
#           email_otp_sent_at: nil,
#           rejection_reason: nil,
#           rejection_notes: nil,
#           rejected_at: nil,
#           rejected_by_admin_id: nil
#         )

#         visitor.selfie.purge if visitor.selfie.attached?
#         visitor.passport_photo.purge if visitor.passport_photo.attached?
#       end

#       issue_otp!(visitor)

#       redirect_to verify_email_public_visitor_path(visitor.public_id),
#                   notice: t("bon_touris.notices.otp_sent")
#     end

#     # ============================================================
#     # RESUME APPLICATION FROM EMAIL
#     # ============================================================
#     def continue
#       email = params[:email].to_s.strip.downcase

#       return redirect_with_error(
#         t("bon_touris.alerts.email_required")
#       ) if email.blank?

#       visitor = VisitorSubmission.resume_for_email(email)

#       return redirect_with_error(
#         t("bon_touris.alerts.email_not_found")
#       ) unless visitor

#       issue_otp!(visitor)
#       flash[:otp_notice] = t("bon_touris.notices.otp_sent")

#       redirect_to verify_email_public_visitor_path(visitor.public_id)
#     end

#     # ============================================================
#     # PRIVATE
#     # ============================================================
#     private

#     def set_visitor
#       @visitor =
#         VisitorSubmission.find_by(public_id: params[:id]) ||
#         VisitorSubmission.find_by(id: params[:id])

#       return if @visitor

#       redirect_to get_started_public_visitors_path,
#                   alert: t("bon_touris.alerts.application_not_found")
#     end

#     def require_access_grant!
#       token = params[:access_token].to_s

#       grant = VisitorAccessGrant.find_by(
#         token: token,
#         visitor_submission_id: @visitor.id
#       )

#       if @visitor.approved?
#         return if grant.present? && !grant.expired?
#       end

#       unless grant&.valid_for_use?
#         redirect_to get_started_public_visitors_path,
#                     alert: t("bon_touris.alerts.session_expired")
#       end
#     end

#     def consume_access_grant!
#       return unless @visitor

#       grant = VisitorAccessGrant.find_by(
#         token: params[:access_token],
#         visitor_submission_id: @visitor.id
#       )

#       return unless grant
#       return if grant.consumed_at.present?

#       grant.consume!
#     end

#     def issue_otp!(visitor)
#       return if visitor.email_otp_sent_at&.>(2.minutes.ago)

#       visitor.generate_email_otp!
#       VisitorMailer.with(visitor: visitor).email_verification.deliver_later
#     end

#     def resolve_layout
#       case action_name
#       when "download_pdf"
#         "pdf"
#       when "success", "get_started", "new", "create", "documents", "documents_submit"
#         "visitor"
#       else
#         "visitor_auth"
#       end
#     end

#     def visitor_params
#       params.require(:visitor_submission).permit(
#         :title, :first_name, :middle_name, :last_name, :dob, :sex,
#         :nationality, :residence_country, :email, :phone,
#         :passport_number, :passport_expiry_date,
#         :purpose_of_visit, :stay_duration_days, :entry_mode,
#         :transport_provider, :transport_reference,
#         :port_of_entry, :accommodation_name, :accommodation_type,
#         address_attributes: %i[
#           street_address department_id arrondissement_id
#           commune_id communal_section_id postal_code country
#         ],
#         local_contact_attributes: %i[
#           name phone phone_country_code email relationship verified user_id
#         ]
#       )
#     end

#     def visitor_submission_params
#       params.require(:visitor_submission).permit(
#         :selfie,
#         :passport_photo,
#         :affirm_information,
#         :selfie_captured_at
#       )
#     end

#     def disable_cache!
#       response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
#       response.headers["Pragma"]        = "no-cache"
#       response.headers["Expires"]       = "0"
#     end

#     def redirect_with_error(message)
#       redirect_to get_started_public_visitors_path, alert: message
#     end
#   end
# end
