# frozen_string_literal: true

module PartnerPortal
  # CEP decryption-key ceremony — generation and one-time printable
  # distribution. The submission/reconstruct side of the ceremony is
  # handled by the existing Election::MultiSigService and the dashboard
  # multi-sig surface; this controller is strictly the
  # generate-and-distribute step.
  #
  # Flow:
  #
  #   GET  /partner_portal/election/:election_id/ceremony
  #        → status: are shards generated yet? how many distributed?
  #
  #   POST /partner_portal/election/:election_id/ceremony/generate
  #        → mints master key, splits 5-of-9, mints per-shard X25519
  #          keypairs, seals shares into envelopes, persists wires +
  #          recipient public keys, and renders the ONE-TIME printable
  #          page directly. Recipient private keys + QR backups exist
  #          ONLY in this response — no GET fetches them later.
  #
  # Authorization: CEP sector + partner_admin role. Mirrors
  # DiplomaticMissionsController#ensure_cep_sector!.
  class CeremonyController < PartnerPortal::BaseController
    before_action :ensure_cep_sector!
    before_action :require_partner_admin!, only: %i[generate]
    before_action :set_election

    # GET /partner_portal/election/:election_id/ceremony
    def show
      @generated = @election.decryption_key_generated?
      @shards    = @election.election_key_shards.order(:role)
      @sig_status = ::Election::MultiSigService.status(@election.id) if @generated
    end

    # GET /partner_portal/election/:election_id/ceremony/submit
    #
    # The ceremony-day submission form for a single CEP council member.
    # Two paths to recover the cleartext shard:
    #   * Envelope: paste the X25519 private key from the printed envelope
    #     → server fetches the matching ElectionKeyShard wire and runs
    #       ShardEnvelope.open
    #   * QR backup: paste / scan the JSON payload from the printed QR
    #     → server runs ShardQrSigner.verify and extracts shard_value
    #
    # Either way the resolved cleartext is forwarded to
    # MultiSigService.add_signature (NEVER rendered back to the user).
    def submit
      @sig_status = ::Election::MultiSigService.status(@election.id)
      @available_roles = @sig_status[:available_roles] ||
                         ::Election::MultiSigService::SIGNATORY_ROLES
    end

    # POST /partner_portal/election/:election_id/ceremony/submit
    def submit_signature
      role     = params[:role].to_s
      bonid    = params[:bonid].to_s.strip
      name     = params[:name].to_s.strip
      mode     = params[:mode].to_s   # "envelope" | "qr"
      liveness_session_id = params[:liveness_session_id].to_s.strip

      # Server-side liveness verification. The form-level "operator
      # confirmed" checkbox is gone — the only acceptable proof is a
      # genuine FaceLivenessService session that AWS Rekognition says
      # PASSED above the strict (non-gray-zone) confidence threshold.
      verify_liveness!(liveness_session_id, bonid: bonid)

      cleartext = resolve_cleartext_shard!(role: role, mode: mode,
                                           private_key: params[:private_key_b64].to_s,
                                           qr_json:     params[:qr_json].to_s)

      result = ::Election::MultiSigService.add_signature(@election.id, {
        bonid:               bonid,
        role:                role,
        name:                name,
        liveness_session_id: liveness_session_id,
        liveness_verified:   true,          # server-decided after verify_liveness!
        key_shard:           cleartext
      })

      audit!("decryption_shard.submitted",
             role: role, bonid: bonid, mode: mode,
             quorum_met: result[:quorum_met],
             count_after: result[:signatures_count])

      if result[:quorum_met]
        redirect_to partner_portal_election_results_path(@election.id),
                    notice: "Kowòm atenn (#{result[:signatures_count]}/5). Rezilta yo disponib."
      else
        redirect_to partner_portal_election_ceremony_path(@election.id),
                    notice: "Siyati anrejistre. #{result[:remaining]} siyati rete."
      end
    rescue ::Election::ShardEnvelope::DecryptError, ::Election::ShardEnvelope::InvalidWireError => e
      audit!("decryption_shard.envelope_failed", role: params[:role], reason: e.class.name)
      redirect_to partner_portal_election_ceremony_submit_path(election_id: @election.id),
                  alert: "Anvlòp pa otantik: #{e.message}"
    rescue ::Election::MultiSigService::DuplicateSignatureError,
           ::Election::MultiSigService::InvalidSignatoryError => e
      audit!("decryption_shard.rejected", role: params[:role], reason: e.class.name, message: e.message)
      redirect_to partner_portal_election_ceremony_submit_path(election_id: @election.id), alert: e.message
    rescue InvalidSubmissionError => e
      redirect_to partner_portal_election_ceremony_submit_path(election_id: @election.id), alert: e.message
    end

    # POST /partner_portal/election/:election_id/ceremony/generate
    #
    # Mints + seals + immediately renders the printable bundle. Uses
    # `regenerate_with_envelopes!` if the caller passes `force=true`
    # (every prior printed envelope becomes worthless).
    def generate
      service = ::Election::DecryptionKeyCeremonyService.new(@election)

      result =
        if ActiveModel::Type::Boolean.new.cast(params[:force])
          service.regenerate_with_envelopes!
        else
          service.generate_with_envelopes!
        end

      @shards    = result[:rows]
      @printable = result[:printable]
      audit!("decryption_keys.generated",
             count:           @shards.size,
             regenerated:     params[:force].present?,
             fingerprint16:   @election.decryption_key_fingerprint.to_s[0, 16])

      # No layout: this page is for printing; no chrome, no nav.
      render :printable, layout: false
    rescue ::Election::DecryptionKeyCeremonyService::AlreadyGeneratedError => e
      redirect_to partner_portal_election_ceremony_path(@election),
                  alert: e.message
    rescue ::Election::DecryptionKeyCeremonyService::GenerationError => e
      Rails.logger.error("[Ceremony] generation failed: #{e.message}")
      redirect_to partner_portal_election_ceremony_path(@election),
                  alert: "Jenerasyon kle echwe: #{e.message}"
    end

    private

    class InvalidSubmissionError < StandardError; end
    class LivenessRequiredError < InvalidSubmissionError; end

    # Reject the submission unless AWS Rekognition Face Liveness says
    # this `liveness_session_id` is a genuine, passed, non-gray-zone
    # session. Audit either outcome before returning.
    #
    # In test/dev where Rekognition isn't wired, set
    # ENV["CEREMONY_BYPASS_LIVENESS"]="1" — DO NOT do this in
    # production. The bypass logs a loud warning every call.
    def verify_liveness!(session_id, bonid:)
      if session_id.blank?
        raise LivenessRequiredError, "ID sesyon liveness obligatwa anvan ou ka soumèt yon shard."
      end

      if ENV["CEREMONY_BYPASS_LIVENESS"] == "1"
        Rails.logger.warn("[Ceremony] LIVENESS BYPASS active for session=#{session_id} bonid=#{bonid} — DEV ONLY")
        audit!("decryption_shard.liveness_bypassed", session_id: session_id, bonid: bonid)
        return
      end

      result = ::FaceLivenessService.get_results(session_id)

      passed = result[:success] && result[:passed] && !result[:needs_review]
      unless passed
        audit!("decryption_shard.liveness_failed",
               session_id: session_id, bonid: bonid,
               status: result[:status], confidence: result[:confidence],
               error: result[:error], needs_review: result[:needs_review])
        raise LivenessRequiredError,
              "Verifikasyon liveness echwe (status=#{result[:status] || 'inconnue'} " \
              "confidence=#{result[:confidence] || 0})."
      end

      audit!("decryption_shard.liveness_passed",
             session_id: session_id, bonid: bonid, confidence: result[:confidence])
    end

    # Resolve the cleartext Shamir share from one of the two paths.
    # NEVER returns the value to the caller's view — only forwards into
    # MultiSigService. Raises on any structural / auth / role mismatch.
    def resolve_cleartext_shard!(role:, mode:, private_key:, qr_json:)
      raise InvalidSubmissionError, "Wòl obligatwa." if role.blank?

      case mode
      when "envelope"
        if private_key.blank?
          raise InvalidSubmissionError, "Kle prive obligatwa pou opsyon anvlòp la."
        end
        shard_row = @election.election_key_shards.find_by(role: role)
        raise InvalidSubmissionError, "Pa gen shard pou wòl sa." if shard_row.nil?
        shard_row.decrypt_with(private_key.strip)

      when "qr"
        if qr_json.blank?
          raise InvalidSubmissionError, "Done QR a obligatwa."
        end
        payload =
          begin
            JSON.parse(qr_json.strip)
          rescue JSON::ParserError
            raise InvalidSubmissionError, "QR a pa yon JSON valab."
          end

        verdict = ::Election::ShardQrSigner.verify(payload)
        unless verdict == :valid
          raise InvalidSubmissionError, "Siyati QR a echwe (#{verdict})."
        end
        if payload["election_id"].to_s != @election.id.to_s
          raise InvalidSubmissionError, "QR sa a se pou yon lòt eleksyon."
        end
        if payload["shard_role"].to_s != role
          raise InvalidSubmissionError, "Wòl QR a pa matche wòl ou chwazi a."
        end
        payload["shard_value"].to_s

      else
        raise InvalidSubmissionError, "Mòd soumèt envalid (chwazi anvlòp oswa QR)."
      end
    end

    def set_election
      @election = BonvoteElection.find(params[:election_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_dashboard_path,
                  alert: "Eleksyon pa jwenn." and return
    end

    # CEP-only surface (mirrors DiplomaticMissionsController).
    def ensure_cep_sector!
      sector = (@current_partner.department_sector || @current_partner.sector).to_s.downcase
      return if sector == "cep"
      redirect_to partner_portal_dashboard_path,
                  alert: "Aksè refize. Sèlman patnè CEP ka jere seremoni dechifraj."
    end

    def require_partner_admin!
      return if current_portal_user&.has_role?(:partner_admin)
      redirect_to partner_portal_dashboard_path,
                  alert: "Sèlman administratè CEP ka deklanche jenerasyon kle."
    end

    def audit!(event, extra = {})
      PartnerAuditLog.log!(@current_partner, current_portal_user, event,
                           { election_id: @election&.id,
                             ip_address:  request.remote_ip,
                             user_agent:  request.user_agent }.merge(extra))
    rescue => e
      Rails.logger.warn("[Ceremony] audit log failed for #{event}: #{e.message}")
    end
  end
end
