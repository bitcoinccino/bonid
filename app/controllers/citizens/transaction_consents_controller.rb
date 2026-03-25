# frozen_string_literal: true

module Citizens
  class TransactionConsentsController < BaseController
    before_action :authenticate_citizen!
    before_action :set_citizen
    before_action :ensure_verified_bonid!, only: [ :decide, :liveness_decide ]
    before_action :set_consent, only: [ :decide, :liveness_decide ]
    before_action :validate_consent_actionable!, only: [ :decide, :liveness_decide ]

    # ================================================================
    # INDEX — List all transaction consents (focus mode + history)
    # ================================================================
    def index
      # Bulk-expire stale pending consents so status column stays accurate
      @citizen.transaction_consents
              .where(status: :pending)
              .where("expires_at <= ?", Time.current)
              .update_all(status: 3)

      base = @citizen.transaction_consents.includes(partner: { logo_attachment: :blob })

      # Single query for all status counts (avoids 3 separate COUNT queries)
      counts = @citizen.transaction_consents.group(:status).count
      @pending_count  = counts["pending"]  || counts[0] || 0
      @approved_count = counts["approved"] || counts[1] || 0
      @denied_count   = counts["denied"]   || counts[2] || 0
      @expired_count  = counts["expired"]  || counts[3] || 0

      # Focus mode: active pending consents (oldest first = most urgent)
      @pending_consents = @citizen.transaction_consents
                                  .active
                                  .includes(partner: { logo_attachment: :blob })
                                  .order(created_at: :asc)

      # Recent completed transactions for "peace of mind" section
      @recent_completed = @citizen.transaction_consents
                                  .where.not(status: :pending)
                                  .includes(partner: { logo_attachment: :blob })
                                  .order(decided_at: :desc)
                                  .limit(3)

      # Apply filter before pagination
      if params[:status].present? && %w[pending approved denied expired].include?(params[:status])
        base = base.where(status: params[:status])
      end

      @transaction_consents = base.order(created_at: :desc).page(params[:page]).per(20)
    end

    # ================================================================
    # DECIDE — Citizen approves or denies with OTP from dashboard
    # ================================================================
    def decide
      otp_code = params[:otp].to_s.strip
      decision = params[:decision].to_s.strip.downcase

      # ── Early input validation (before hitting BCrypt) ──
      unless %w[approve deny].include?(decision)
        return respond_with_error("Invalid decision.")
      end

      if otp_code.blank?
        return respond_with_error("Please enter your 6-digit approval code.")
      end

      unless otp_code.match?(/\A\d{6}\z/)
        return respond_with_error("Code must be exactly 6 digits.")
      end

      result = TransactionConsentService.verify_and_decide!(
        consent: @consent,
        otp_code: otp_code,
        decision: decision,
        ip: request.remote_ip
      )

      @consent = result

      # Recalculate counts for Turbo Stream badge updates
      counts = @citizen.transaction_consents.group(:status).count
      @pending_count  = counts["pending"]  || counts[0] || 0
      @approved_count = counts["approved"] || counts[1] || 0
      @denied_count   = counts["denied"]   || counts[2] || 0
      @expired_count  = counts["expired"]  || counts[3] || 0

      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = decision == "approve" ?
            "Transaction approved for #{@consent.partner.name}." :
            "Transaction denied for #{@consent.partner.name}."
        end
        format.html do
          msg = decision == "approve" ? "Transaction approved." : "Transaction denied."
          redirect_to citizens_transaction_consents_path, notice: msg
        end
      end

    rescue TransactionConsentService::ExpiredError
      respond_with_error("This request has expired.")

    rescue TransactionConsentService::LockedError
      respond_with_error("Too many attempts. This request is locked.")

    rescue TransactionConsentService::InvalidOtpError => e
      respond_with_error(e.message)
    end

    # ================================================================
    # LIVENESS DECIDE — Citizen approves via face biometric verification
    # ================================================================
    def liveness_decide
      # Trust the server-side session metadata populated by liveness_status
      # instead of re-calling AWS (which rejects duplicate get_results calls).
      metadata = session[:liveness_metadata]
      param_session_id = params[:liveness_session_id].to_s.strip

      # Try session metadata first (preferred), fall back to live AWS call
      if metadata && metadata["passed"]
        liveness_session_id = metadata["session_id"]
        confidence = metadata["confidence"]
        Rails.logger.info "[liveness_decide] Using verified session metadata: #{liveness_session_id} (#{confidence}%)"
      elsif param_session_id.present? && param_session_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        # Fallback: try AWS directly (only if it's a valid UUID, not a blob signed ID)
        result = FaceLivenessService.get_results(param_session_id)
        unless result[:success] && result[:passed]
          return respond_with_error(t("transaction_consents.liveness_failed"))
        end
        liveness_session_id = param_session_id
        confidence = result[:confidence]
      else
        return respond_with_error(t("transaction_consents.liveness_failed"))
      end

      # ── FACE COMPARISON: Verify liveness selfie matches citizen's ID ──
      # The liveness check proves a real person is present. This step proves
      # it's the RIGHT person — the citizen who owns the BonID.
      approved_submission = @citizen.identity_submissions.find_by(status: :approved)
      liveness_blob_signed_id = session[:liveness_blob_signed_id]

      if approved_submission && liveness_blob_signed_id.present?
        liveness_blob = ActiveStorage::Blob.find_signed(liveness_blob_signed_id)
        if liveness_blob
          liveness_bytes = liveness_blob.download rescue nil

          # Get the citizen's ID photo — prefer CIN/passport (the actual document),
          # fall back to selfie from BonID application
          if approved_submission.cin_front.attached?
            id_attachment = approved_submission.cin_front
            compared_against = "cin_front"
          elsif approved_submission.passport.attached?
            id_attachment = approved_submission.passport
            compared_against = "passport"
          elsif approved_submission.selfie.attached?
            id_attachment = approved_submission.selfie
            compared_against = "bonid_selfie"
          else
            id_attachment = nil
          end

          if liveness_bytes && id_attachment
            id_bytes = id_attachment.blob.download rescue nil

            if id_bytes
              begin
                compare_response = FaceMatchService.rekognition_client.compare_faces(
                  source_image: { bytes: liveness_bytes },
                  target_image: { bytes: id_bytes },
                  similarity_threshold: 0
                )

                if compare_response.face_matches.any?
                  best_match = compare_response.face_matches.max_by(&:similarity)
                  face_similarity = best_match.similarity.round(2)

                  if face_similarity < FaceMatchService::SIMILARITY_THRESHOLD
                    Rails.logger.warn "[liveness_decide] FACE MISMATCH: Consent #{@consent.consent_token} — similarity #{face_similarity}% < #{FaceMatchService::SIMILARITY_THRESHOLD}% threshold"
                    return respond_with_error("Figi ou pa matche ak idantite BonID ou. Tanpri eseye ankò.")
                  end

                  Rails.logger.info "[liveness_decide] Face matched: #{face_similarity}% for consent #{@consent.consent_token}"
                else
                  Rails.logger.warn "[liveness_decide] NO FACE MATCH: No matching faces found for consent #{@consent.consent_token}"
                  return respond_with_error("Figi ou pa matche ak idantite BonID ou. Tanpri eseye ankò.")
                end
              rescue Aws::Rekognition::Errors::ServiceError => e
                Rails.logger.error "[liveness_decide] Face comparison AWS error: #{e.message} — allowing consent (liveness passed)"
                # Don't block on AWS errors — liveness already passed
              end
            end
          end
        end
      end

      # Approve the consent with biometric proof
      @consent.approve_with_biometric!(
        ip: request.remote_ip,
        liveness_session_id: liveness_session_id,
        confidence: confidence,
        face_similarity: defined?(face_similarity) ? face_similarity : nil,
        compared_against: defined?(compared_against) ? compared_against : nil
      )

      # Clear session metadata to prevent replay attacks
      session.delete(:liveness_metadata)
      session.delete(:liveness_session_id)
      session.delete(:liveness_blob_signed_id)

      # Send approval email
      Citizens::TransactionConsentMailer
        .with(consent: @consent)
        .consent_approved
        .deliver_later

      # Notify partner via webhook callback
      BonidNotifier.notify_transaction_consent(@consent)

      # Recalculate counts for Turbo Stream badge updates
      counts = @citizen.transaction_consents.group(:status).count
      @pending_count  = counts["pending"]  || counts[0] || 0
      @approved_count = counts["approved"] || counts[1] || 0
      @denied_count   = counts["denied"]   || counts[2] || 0
      @expired_count  = counts["expired"]  || counts[3] || 0

      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = t("transaction_consents.approved_message", partner: @consent.partner.name)
        end
        format.html do
          redirect_to citizens_transaction_consents_path,
                      notice: t("transaction_consents.approved_message", partner: @consent.partner.name)
        end
      end
    rescue => e
      Rails.logger.error("[liveness_decide] Error: #{e.message}")
      respond_with_error(t("transaction_consents.liveness_failed"))
    end

    private

    def set_citizen
      @citizen = current_citizen
    end

    # Block unverified citizens from approving/denying transactions
    def ensure_verified_bonid!
      unless @citizen&.bonid_verified?
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "flash-messages",
              html: helpers.content_tag(:div, "You must verify your BonID before approving or denying transactions.",
                                       class: "alert alert-warning border-0 rounded-3 small mb-3")
            )
          end
          format.html do
            redirect_to citizens_identity_submissions_path,
                        alert: "You must verify your BonID before approving or denying transactions."
          end
        end
      end
    end

    def set_consent
      @consent = @citizen.transaction_consents
                         .includes(:partner)
                         .find_by!(consent_token: params[:consent_token])
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "flash-messages",
            html: helpers.content_tag(:div, "Transaction request not found.", class: "alert alert-danger border-0 rounded-3 small mb-3")
          )
        end
        format.html { redirect_to citizens_transaction_consents_path, alert: "Transaction request not found." }
      end
    end

    # ── Catch expired/locked/already-decided BEFORE touching BCrypt ──
    def validate_consent_actionable!
      return unless @consent

      unless @consent.pending?
        return respond_with_error("This request was already #{@consent.status}.")
      end

      if @consent.expires_at < Time.current
        @consent.update_column(:status, 3) # expired
        return respond_with_error("This request has expired.")
      end

      if @consent.otp_locked?
        return respond_with_error("Too many attempts. This request is locked.")
      end
    end

    def respond_with_error(message)
      respond_to do |format|
        format.turbo_stream do
          if @consent&.consent_token
            render turbo_stream: turbo_stream.update(
              "otp-error-#{@consent.consent_token}",
              html: helpers.content_tag(:div, message, class: "alert alert-danger border-0 rounded-3 py-2 px-3 small mb-0")
            )
          else
            render turbo_stream: turbo_stream.update(
              "flash-messages",
              html: helpers.content_tag(:div, message, class: "alert alert-danger border-0 rounded-3 small mb-3")
            )
          end
        end
        format.html { redirect_to citizens_transaction_consents_path, alert: message }
      end
    end
  end
end
