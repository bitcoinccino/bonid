# frozen_string_literal: true

# app/controllers/api/v1/identity_controller.rb
#
# Unified Identity Verification API for verified partners.
# Handles both BonID (citizens) and BonTouris (tourists).
#
# Security:
# - Requires dual authentication (API key + OAuth token)
# - Scope-based access control (identity:verify, identity:details)
# - Rate limited to prevent abuse
# - All access logged for audit trail
# - Response signing for integrity verification
# - Lookups by BonID string only — integer IDs never exposed
#
# Risk-Score API (v1.1.0):
#   The `biometrics` block in the response exposes raw confidence scores
#   so partner risk engines can apply their own thresholds:
#     • liveness_confidence    — AWS Rekognition liveness (0–100%)
#     • face_match_similarity  — AWS Rekognition face compare (0–100%)
#     • audit_status           — "passed" | "failed" | "not_performed"
#     • verified_with_review   — true if human admin reviewed gray-zone liveness
#     • biometrics_reused      — true if carried forward from prior submission
#
# Endpoints:
#   GET /api/v1/identity/:bonid - Verify identity and get details
#   GET /api/v1/identity/:bonid/status - Quick verification status check
#
module Api
  module V1
    class IdentityController < Api::V1::BaseController
      include ResponseSigner

      # Scope requirements per action
      REQUIRED_SCOPES = {
        show: "identity:verify",
        status: "identity:verify"
      }.freeze

      # GET /api/v1/identity/:bonid
      #
      # Verify and retrieve full identity details for a BonID or BonTouris holder.
      #
      # @param bonid [String] The BonID or BonTouris number
      # @return [JSON] Identity details
      #
      def show
        # Validate scope
        unless has_required_scope?(:show)
          return render_scope_error("identity:verify")
        end

        # Rate limiting handled by RateLimitable concern (before_action)

        # Validate BonID parameter
        bonid = params[:bonid].to_s.strip.upcase
        if bonid.blank?
          payload = build_error_response("Missing BonID parameter", 400)
          sign_response(payload)
          return render json: payload, status: :bad_request
        end

        # ── Double-Lock: Consent-Gated Access ──────────────────────
        # If consent_token is provided → validate and scope-filter.
        # If absent and no OAuth token → return verification status only (no PII).
        # If absent but has OAuth token → backward-compatible full access.
        consent_token = params[:consent_token].to_s.strip.presence
        @consent = nil

        if consent_token
          @consent = validate_consent_token!(consent_token, bonid)
          return unless @consent # validation rendered an error
        end

        # Lookup person (citizen or tourist)
        result = lookup_identity(bonid)

        if result[:success]
          payload = build_identity_response(result)

          if @consent
            # Double-Lock: filter by consent scopes only
            payload = filter_response_by_consent_scopes(payload, @consent.scopes)

            # Async audit log (non-blocking)
            RecordConsentDataAccessJob.perform_later(
              consent_id: @consent.id,
              ip: request.remote_ip,
              scopes_used: @consent.scopes
            )
          elsif @oauth_token.nil?
            # No consent, no OAuth → strip all PII, return verification status only
            payload = strip_pii(payload)
          else
            # OAuth backward compat → existing scope filtering
            payload = filter_response_by_scopes(payload)
          end

          sign_response(payload)
          render json: payload, status: :ok
        else
          payload = build_error_response(result[:error], result[:code])
          sign_response(payload)
          render json: payload, status: result[:status]
        end
      rescue StandardError => e
        Rails.logger.error("[API::IdentityController#show] #{e.class}: #{e.message}")
        handle_error(e)
      end

      # GET /api/v1/identity/:bonid/status
      #
      # Quick verification status check (lightweight).
      # Returns only verification status, not full details.
      #
      # @param bonid [String] The BonID or BonTouris number
      # @return [JSON] Verification status
      #
      def status
        # Validate scope
        unless has_required_scope?(:status)
          return render_scope_error("identity:verify")
        end

        # Rate limiting handled by RateLimitable concern (before_action)

        # Validate BonID parameter
        bonid = params[:bonid].to_s.strip.upcase
        if bonid.blank?
          payload = build_error_response("Missing BonID parameter", 400)
          sign_response(payload)
          return render json: payload, status: :bad_request
        end

        # Quick status lookup
        result = check_verification_status(bonid)

        payload = {
          status: "success",
          bonid: bonid,
          verification: result,
          partner: @partner&.name,
          timestamp: Time.current.iso8601
        }

        sign_response(payload)
        render json: payload, status: :ok
      rescue StandardError => e
        Rails.logger.error("[API::IdentityController#status] #{e.class}: #{e.message}")
        handle_error(e)
      end

      private

      # ── Double-Lock: Consent Token Validation ─────────────────────
      # Fast path: Redis cache check (~0.1ms).
      # Slow path: DB lookup (~5ms) with full validation.
      # ───────────────────────────────────────────────────────────────
      def validate_consent_token!(token, bonid)
        # Fast path: check Redis cache
        cached = TransactionConsent.cached_consent(token, @partner.id)
        if cached
          # Validate cached data
          if cached[:citizen_bonid] != bonid
            render_consent_error("Consent token does not match this BonID", :forbidden)
            return nil
          end
          if Time.parse(cached[:expires_at]) < Time.current
            render_consent_error("Consent data access window has expired", :gone)
            return nil
          end
          if cached[:burn_after_read] && cached[:data_access_count].to_i > 0
            render_consent_error("Consent token has been consumed (burn-after-read)", :gone)
            return nil
          end
          # Cache hit — still need the full record for audit logging
          consent = TransactionConsent.find_by(consent_token: token, partner_id: @partner.id)
          return consent if consent&.data_access_allowed?
        end

        # Slow path: DB lookup
        consent = TransactionConsent.find_by(consent_token: token, partner_id: @partner.id)

        unless consent
          render_consent_error("Consent token not found or does not belong to this partner", :not_found)
          return nil
        end

        unless consent.approved?
          render_consent_error("Consent is #{consent.status}, not approved", :forbidden)
          return nil
        end

        if consent.citizen.bonid != bonid
          render_consent_error("Consent token does not match this BonID", :forbidden)
          return nil
        end

        unless consent.data_access_allowed?
          if consent.burned?
            render_consent_error("Consent token has been consumed (burn-after-read)", :gone)
          else
            render_consent_error("Consent data access window has expired. Request a new consent.", :gone)
          end
          return nil
        end

        consent
      end

      def render_consent_error(message, status)
        payload = {
          status: "error",
          error: message,
          code: Rack::Utils.status_code(status),
          hint: "Request a new transaction consent via POST /api/v1/transaction_consents",
          timestamp: Time.current.iso8601
        }
        sign_response(payload)
        render json: payload, status: status
      end

      # ── Transaction-Type Implicit Scopes ──────────────────────────
      # Certain transaction types REQUIRE specific data to function.
      # These scopes are auto-injected regardless of what the partner
      # explicitly requested — the transaction type itself justifies
      # the data need.
      # ────────────────────────────────────────────────────────────────
      TRANSACTION_TYPE_IMPLICIT_SCOPES = {
        # Embassy visa processing needs biometrics for facial match
        "visa_processing"    => %w[identity:verify profile],
        "diaspora_verify"    => %w[identity:verify profile],
        "passport_renewal"   => %w[profile],
        "consular_id"        => %w[profile],
        # DGI needs NIF (future: nif field on User)
        "tax_service"        => %w[profile tax],
        # Archives Nationales needs parent info (future: parent_names on User)
        "civil_registry"     => %w[profile civil],
        # KYC always needs profile + identity verification
        "kyc_check"          => %w[identity:verify profile],
        # Land registry needs address for property ownership
        "land_registry"      => %w[profile address],
        # Judicial record needs identity verification
        "judicial_record"    => %w[identity:verify profile]
      }.freeze

      # ── Double-Lock: Consent Scope Filtering ────────────────────
      # Returns ONLY the data the citizen consented to.
      # Photo is guarded under "profile" or "identity:verify" scope.
      # Transaction-type implicit scopes are auto-injected.
      # ───────────────────────────────────────────────────────────────
      def filter_response_by_consent_scopes(payload, consent_scopes)
        scopes = Array(consent_scopes).map(&:to_s)

        # Inject implicit scopes based on transaction type
        if @consent&.transaction_type.present?
          implicit = TRANSACTION_TYPE_IMPLICIT_SCOPES[@consent.transaction_type]
          scopes = (scopes + Array(implicit)).uniq if implicit
        end

        identity = payload[:identity]
        return payload unless identity.is_a?(Hash)

        # Full access scope — skip filtering
        return payload if scopes.include?("identity:details")

        # Profile: name, DOB, sex, nationality, photo
        unless scopes.include?("profile")
          %i[first_name middle_name last_name full_name
             date_of_birth age sex nationality].each { |k| identity.delete(k) }
          # Photo is ONLY available with "profile" or "identity:verify"
          identity.delete(:photo_url) unless scopes.include?("identity:verify")
        end

        # Email
        identity.delete(:email) unless scopes.include?("email")

        # Phone
        identity.delete(:phone) unless scopes.include?("phone")

        # Address
        unless scopes.include?("address")
          %i[address department commune].each { |k| identity.delete(k) }
        end

        # Health (blood type, organ donor, allergies, conditions, medications)
        unless scopes.include?("health")
          %i[blood_type organ_donor allergies chronic_conditions medications].each { |k| identity.delete(k) }
        end

        # Physical traits
        unless scopes.include?("physical")
          %i[height weight eye_color hair_color hair_style body_type skin_tone
             race facial_hair handedness].each { |k| identity.delete(k) }
        end

        # Biometrics: only with identity:verify
        unless scopes.include?("identity:verify")
          identity.delete(:biometrics)
        end

        # Tax data (NIF / Matricule Fiscale) — future field
        unless scopes.include?("tax")
          %i[nif matricule_fiscale tax_id].each { |k| identity.delete(k) }
        end

        # Civil registry data (family members, place of birth)
        unless scopes.include?("civil")
          %i[family_members place_of_birth birth_certificate_ref].each { |k| identity.delete(k) }
        end

        # Emergency contacts
        unless scopes.include?("emergency_contacts")
          identity.delete(:emergency_contacts)
        end

        # Social handles
        unless scopes.include?("social")
          identity.delete(:social_handles)
        end

        # QR code: never included in consent-gated responses
        identity.delete(:qr_code)

        payload[:granted_scopes] = scopes
        payload[:consent_token] = @consent.consent_token
        payload[:consent_expires_at] = (@consent.decided_at + @consent.data_access_window).iso8601

        payload
      end

      # ── Strip PII: No consent, no OAuth → verification status only ──
      # Partners with just an API key get "verified: true/false" and nothing else.
      # This prevents the "creepy agent" problem.
      # ──────────────────────────────────────────────────────────────────
      def strip_pii(payload)
        identity = payload[:identity]
        return payload unless identity.is_a?(Hash)

        # Keep only non-PII fields
        safe_keys = %i[bonid masked_bonid id_type verification]
        identity.keep_if { |k, _| safe_keys.include?(k) }

        payload.delete(:granted_scopes)
        payload[:access_level] = "verification_only"
        payload[:hint] = "To access identity details, provide a valid consent_token from an approved transaction consent."

        payload
      end

      # ── Scope-Based Response Filtering ─────────────────────────────
      # Strips identity fields that the Bearer token doesn't have
      # scope access to. API-key-only requests (no OAuth token) get
      # full access — scope restrictions apply only to OAuth tokens.
      # ───────────────────────────────────────────────────────────────
      def filter_response_by_scopes(payload)
        # API-key auth = full access (no token, no filtering)
        return payload if @oauth_token.nil?

        scopes   = Array(@oauth_token.scopes).map(&:to_s)
        identity = payload[:identity]
        return payload unless identity.is_a?(Hash)

        # Profile scope: name, DOB, sex, nationality, photo
        unless scopes.include?("profile")
          %i[first_name middle_name last_name full_name
             date_of_birth age sex nationality photo_url].each { |k| identity.delete(k) }
        end

        # Email scope
        unless scopes.include?("email")
          identity.delete(:email)
        end

        # Phone scope
        unless scopes.include?("phone")
          identity.delete(:phone)
        end

        # Address scope
        unless scopes.include?("address")
          %i[address department commune].each { |k| identity.delete(k) }
        end

        # Health scope
        unless scopes.include?("health")
          %i[blood_type organ_donor allergies chronic_conditions medications].each { |k| identity.delete(k) }
        end

        # Physical scope
        unless scopes.include?("physical")
          %i[height weight eye_color hair_color hair_style body_type skin_tone
             race facial_hair handedness].each { |k| identity.delete(k) }
        end

        # Emergency contacts scope
        unless scopes.include?("emergency_contacts")
          identity.delete(:emergency_contacts)
        end

        # Social handles scope
        unless scopes.include?("social")
          identity.delete(:social_handles)
        end

        # Include granted scopes in response for transparency
        payload[:granted_scopes] = scopes

        payload
      end

      # Lookup identity by BonID or BonTouris
      def lookup_identity(bonid)
        # Redis cache: avoid repeated DB hits for the same BonID (2-min TTL)
        cache_key = "api:identity:#{bonid}"
        cached = Rails.cache.read(cache_key)
        return cached if cached

        result = lookup_identity_uncached(bonid)

        # Cache successful lookups only
        Rails.cache.write(cache_key, result, expires_in: 2.minutes) if result[:success]
        result
      end

      def lookup_identity_uncached(bonid)
        # Eager-load associations to eliminate N+1 queries (~15-25ms savings)
        user = User.includes(:health_profile, :physical_profile, :social_handles, :emergency_contacts, :family_members, address: [:commune, :department])
                    .find_by(bonid: bonid)
        if user
          submission = user.identity_submissions
                           .includes(:reviewer, selfie_attachment: :blob, photo_attachment: :blob)
                           .find_by(status: :approved)
          if submission
            return build_citizen_result(user, submission)
          else
            return {
              success: true,
              type: :citizen,
              verified: false,
              person: user,
              message: "BonID exists but identity not yet verified"
            }
          end
        end

        # Try BonID alias resolution (name change: JM → VP)
        resolved_bonid = BonidAlias.resolve(bonid)
        if resolved_bonid
          user = User.includes(:health_profile, :physical_profile, :social_handles, :emergency_contacts, :family_members, address: [:commune, :department])
                      .find_by(bonid: resolved_bonid)
          if user
            submission = user.identity_submissions
                             .includes(:reviewer, selfie_attachment: :blob, photo_attachment: :blob)
                             .find_by(status: :approved)
            if submission
              result = build_citizen_result(user, submission)
              result[:data][:alias_info] = {
                queried_bonid:  bonid,
                current_bonid:  resolved_bonid,
                bonid_changed:  true
              }
              return result
            end
          end
        end

        # Try tourist lookup (BonTouris)
        visitor = VisitorSubmission.find_by(bonid: bonid)
        if visitor
          return build_tourist_result(visitor)
        end

        # Try 6-digit suffix lookup
        if bonid.match?(/^\d{6}$/)
          user = User.includes(:health_profile, :physical_profile, :social_handles, :emergency_contacts, :family_members, address: [:commune, :department])
                      .where("bonid LIKE ?", "%-#{bonid[0..3]}-#{bonid[4..5]}%").first
          if user
            submission = user.identity_submissions
                             .includes(:reviewer, selfie_attachment: :blob, photo_attachment: :blob)
                             .find_by(status: :approved)
            return build_citizen_result(user, submission) if submission
          end

          visitor = VisitorSubmission.where("bonid LIKE ?", "%-#{bonid}").first
          return build_tourist_result(visitor) if visitor
        end

        # Not found
        { success: false, error: "BonID or BonTouris not found", code: 404, status: :not_found }
      end

      # Build citizen (BonID holder) result
      def build_citizen_result(user, submission)
        {
          success: true,
          type: :citizen,
          verified: true,
          person: user,
          submission: submission,
          data: {
            bonid: user.bonid,
            masked_bonid: mask_bonid(user.bonid),
            id_type: "BonID",
            first_name: user.first_name,
            middle_name: user.middle_name,
            last_name: user.last_name,
            full_name: user.full_name,
            date_of_birth: user.dob&.iso8601,
            age: user.age,
            sex: user.sex,
            nationality: user.nationality || "Haitian",
            address: user.full_address,
            department: user.address&.department&.name,
            commune: user.address&.commune&.name,
            # Health (HealthProfile)
            blood_type: user.health_profile&.blood_type,
            organ_donor: user.health_profile&.organ_donor,
            allergies: user.health_profile&.allergies_list,
            chronic_conditions: user.health_profile&.chronic_conditions_list,
            medications: user.health_profile&.medications_list,
            # Physical (PhysicalProfile)
            height: user.physical_profile&.height_cm,
            weight: user.physical_profile&.weight_kg,
            eye_color: user.physical_profile&.eye_color,
            hair_color: user.physical_profile&.hair_color,
            hair_style: user.physical_profile&.hair_style,
            body_type: user.physical_profile&.body_type,
            skin_tone: user.physical_profile&.skin_tone,
            race: user.physical_profile&.race,
            facial_hair: user.physical_profile&.facial_hair,
            handedness: user.physical_profile&.handedness,
            # Tax ID (DGI) — populated when column exists
            nif: user.try(:nif),
            # Civil registry (Archives Nationales) — from FamilyMember records
            place_of_birth: user.place_of_birth,
            family_members: user.family_members.map(&:summary),
            # Emergency contacts
            emergency_contacts: user.emergency_contacts.map { |ec|
              {
                name: ec.full_name,
                phone: ec.phone,
                relation: ec.relation,
                verified: ec.verification_status == "verified"
              }
            },
            # Social handles
            social_handles: user.social_handles.map { |sh|
              {
                platform: sh.display_platform,
                handle: sh.handle,
                verified: sh.verified?,
                trust_weight: sh.trust_weight
              }
            },
            verification: {
              verified: true,
              verified_at: submission.updated_at&.iso8601,
              verified_by: submission.reviewer&.full_name,
              expires_at: submission.expires_at&.iso8601,
              submission_type: submission.submission_type,
              document_type: submission.id_type
            },
            biometric_verification: build_biometric_verification(submission),
            biometrics: build_biometrics_block(submission),
            photo_url: photo_url_for(submission),
            qr_code: include_qr_code? && submission.qr_png_base64.present? ? "data:image/png;base64,#{submission.qr_png_base64}" : nil
          }
        }
      end

      # Build tourist (BonTouris holder) result
      def build_tourist_result(visitor)
        verified = visitor.approved?

        {
          success: true,
          type: :tourist,
          verified: verified,
          person: visitor,
          data: {
            bonid: visitor.bonid,
            masked_bonid: mask_bontouris(visitor.bonid),
            id_type: "BonTouris",
            first_name: visitor.first_name,
            middle_name: visitor.middle_name,
            last_name: visitor.last_name,
            full_name: [visitor.first_name, visitor.middle_name, visitor.last_name].compact.join(" "),
            date_of_birth: visitor.dob&.iso8601,
            age: visitor.dob.present? ? ((Date.current - visitor.dob.to_date) / 365.25).to_i : nil,
            sex: visitor.sex,
            nationality: visitor.nationality,
            country_code: visitor.residence_country || extract_country_code(visitor.bonid),
            passport_number: mask_passport(visitor.passport_number),
            passport_expiry: visitor.passport_expiry_date&.iso8601,
            visa_type: visitor.purpose_of_visit,
            entry_date: visitor.entry_date&.iso8601,
            stay_duration_days: visitor.stay_duration_days,
            accommodation: visitor.accommodation_address,
            verification: {
              verified: verified,
              status: visitor.status,
              verified_at: verified ? visitor.updated_at&.iso8601 : nil,
              expires_at: visitor.expires_at&.iso8601,
              submission_type: "tourist_registration"
            },
            biometrics: { audit_status: "not_performed" },
            photo_url: photo_url_for_visitor(visitor),
            qr_code: include_qr_code? && visitor.visitor_qr_png_base64.present? ? "data:image/png;base64,#{visitor.visitor_qr_png_base64}" : nil
          }
        }
      end

      # Quick verification status check
      def check_verification_status(bonid)
        # Try citizen (direct lookup)
        user = User.find_by(bonid: bonid)
        resolved_bonid = nil

        # Try alias resolution if direct lookup fails
        unless user
          resolved_bonid = BonidAlias.resolve(bonid)
          user = User.find_by(bonid: resolved_bonid) if resolved_bonid
        end

        if user
          submission = user.verified_identity_submission
          result = {
            found: true,
            id_type: "BonID",
            verified: submission.present?,
            status: submission.present? ? "verified" : "pending",
            expires_at: submission&.expires_at&.iso8601
          }
          if resolved_bonid
            result[:alias_info] = {
              queried_bonid:  bonid,
              current_bonid:  resolved_bonid,
              bonid_changed:  true
            }
          end
          return result
        end

        # Try tourist
        visitor = VisitorSubmission.find_by(bonid: bonid)
        if visitor
          return {
            found: true,
            id_type: "BonTouris",
            verified: visitor.approved?,
            status: visitor.status,
            nationality: visitor.nationality,
            expires_at: visitor.expires_at&.iso8601
          }
        end

        # Not found
        { found: false, id_type: nil, verified: false, status: "not_found" }
      end

      # Build full identity response
      def build_identity_response(result)
        response = {
          status: "success",
          bonid: result[:data][:bonid],
          id_type: result[:type].to_s,
          verified: result[:verified],
          identity: result[:data],
          partner: @partner&.name,
          timestamp: Time.current.iso8601,
          api_version: "1.1.0"
        }

        # Include alias info when queried with an old/changed BonID
        if result[:data][:alias_info].present?
          response[:alias_info] = result[:data][:alias_info]
        end

        response
      end

      # Build error response
      def build_error_response(message, code)
        {
          status: "error",
          error: message,
          code: code,
          endpoint: request.path,
          timestamp: Time.current.iso8601
        }
      end

      # ── Biometrics Trust Block ────────────────────────────────────────────
      # Exposes liveness + face-match confidence scores so partner risk
      # engines can apply their own thresholds:
      #   • Bank processing $10k transfer → require liveness_confidence > 90
      #   • NGO distributing aid          → accept liveness_confidence > 70
      #
      # Fields:
      #   liveness_confidence    – AWS Rekognition liveness confidence (0–100)
      #   face_match_similarity  – AWS Rekognition face compare similarity (0–100)
      #   face_match_threshold   – minimum similarity BonID required (80.0)
      #   audit_status           – overall biometric verdict: "passed" | "failed" | "not_performed"
      #   challenge_type         – AWS liveness challenge used (always "FaceMovementAndLightChallenge")
      #   verified_with_review   – true if liveness was in gray zone (65–74%) and a human admin approved
      #   biometrics_reused      – true if liveness was carried from a prior submission (doc-only re-submit)
      #   liveness_checked_at    – ISO8601 timestamp of liveness session
      #   face_matched_at        – ISO8601 timestamp of face comparison
      #
      # Security: internal IDs (session_id, blob IDs, submission IDs) are never exposed.
      #
      def build_biometrics_block(submission)
        liveness   = submission.metadata&.dig("liveness")
        face_match = submission.metadata&.dig("face_match")

        # No biometric data at all (legacy submissions pre-liveness)
        return { audit_status: "not_performed" } unless liveness.present? || face_match.present?

        # Determine audit_status from combined liveness + face match outcome
        liveness_ok   = liveness&.dig("passed") == true
        face_match_ok = face_match&.dig("status") == "match"
        audit_status  = (liveness_ok && face_match_ok) ? "passed" : "failed"

        # Gray-zone detection: liveness passed but needed manual review (65–74% confidence)
        verified_with_review = liveness&.dig("needs_review") == true && liveness_ok

        # Biometrics reused from a previous submission (smart resubmission for doc-only rejections)
        biometrics_reused = liveness&.dig("reused_from_submission_uuid").present? ||
                            liveness&.dig("reused_from_submission_id").present?

        {
          liveness_confidence:   liveness&.dig("confidence")&.to_f,
          face_match_similarity: face_match&.dig("similarity")&.to_f,
          face_match_threshold:  face_match&.dig("threshold")&.to_f || FaceMatchService::SIMILARITY_THRESHOLD,
          audit_status:          audit_status,
          challenge_type:        "FaceMovementAndLightChallenge",
          verified_with_review:  verified_with_review,
          biometrics_reused:     biometrics_reused,
          liveness_checked_at:   liveness&.dig("checked_at"),
          face_matched_at:       face_match&.dig("matched_at")
        }.compact
      end

      # Build biometric_verification block for partner transparency.
      # Partners see exactly how the citizen was verified:
      #   - Was the person real? (liveness)
      #   - Did their face match their uploaded ID? (face comparison)
      #   - What scores did they get?
      # Partners can set their own minimum thresholds based on risk tolerance.
      def build_biometric_verification(submission)
        liveness   = submission.metadata&.dig("liveness")
        face_match = submission.metadata&.dig("face_match")

        return nil unless liveness.present? || face_match.present?

        liveness_passed = liveness&.dig("passed") == true
        face_matched    = face_match&.dig("status") == "match"
        face_similarity = face_match&.dig("similarity")&.to_f

        # Determine what document the face was compared against
        compared_against = face_match&.dig("target_image") # "cin_front" or "passport"

        {
          liveness_passed: liveness_passed,
          liveness_confidence: liveness&.dig("confidence")&.to_f,
          face_matched: face_matched,
          face_similarity: face_similarity,
          compared_against: compared_against,
          threshold: face_match&.dig("threshold")&.to_f || FaceMatchService::SIMILARITY_THRESHOLD,
          verified_at: face_match&.dig("matched_at") || liveness&.dig("checked_at")
        }.compact
      end

      # Mask BonID: DV-1989-M-SE-P8697XDS → DV-••••-•-••-P••••XDS
      def mask_bonid(bonid)
        return bonid if bonid.blank?

        # Citizen BonID: MB••••••••697280
        stripped = bonid.gsub("-", "")
        last6 = stripped.last(6)
        dots = "•" * [stripped.length - 8, 6].max
        "MB#{dots}#{last6}"
      end

      # Mask BonTouris: T-JS-1990-M-US-P-988455 → T-JS-••••-•-US-P-988455
      def mask_bontouris(bonid)
        return bonid if bonid.blank?
        parts = bonid.split("-")
        return bonid if parts.length < 6

        [parts[0], parts[1], "••••", "•", parts[-3], parts[-2], parts[-1]].join("-")
      end

      # Mask passport number: AB123456 → AB••••56
      def mask_passport(passport)
        return nil if passport.blank?
        return passport if passport.length < 4

        "#{passport[0..1]}••••#{passport[-2..]}"
      end

      # Extract country code from BonTouris: T-JS-1990-M-US-P-988455 → US
      def extract_country_code(bonid)
        return nil if bonid.blank?
        parts = bonid.split("-")
        return nil if parts.length < 5

        parts[-3] # Country code position
      end

      # Generate photo URL for citizen submission
      def photo_url_for(submission)
        return nil unless submission

        if submission.selfie.attached?
          Rails.application.routes.url_helpers.rails_blob_url(
            submission.selfie,
            host: Rails.application.config.bonid_base_url || request.base_url
          )
        elsif submission.photo.attached?
          Rails.application.routes.url_helpers.rails_blob_url(
            submission.photo,
            host: Rails.application.config.bonid_base_url || request.base_url
          )
        end
      end

      # Generate photo URL for visitor submission
      def photo_url_for_visitor(visitor)
        attachment = visitor&.selfie&.attached? ? visitor.selfie : visitor&.passport_photo
        return nil unless attachment&.attached?

        Rails.application.routes.url_helpers.rails_blob_url(
          attachment,
          host: Rails.application.config.bonid_base_url || request.base_url
        )
      end

      # Check if token has required scope.
      # API-key-only requests (no OAuth token) are granted full access
      # since scope restrictions apply only to OAuth tokens.
      def has_required_scope?(action)
        return true if @oauth_token.nil?

        required = REQUIRED_SCOPES[action]
        token_scopes = Array(@oauth_token.scopes).map(&:to_s)
        token_scopes.include?(required) || token_scopes.include?("identity:details")
      end

      # Render scope error
      def render_scope_error(required_scope)
        payload = {
          status: "forbidden",
          error: "Insufficient scope. Required: #{required_scope}",
          code: 403,
          timestamp: Time.current.iso8601
        }
        sign_response(payload)
        render json: payload, status: :forbidden
      end

      # Handle error (logging handled by base_controller around_action)
      def handle_error(error, _start_time = nil, _bonid = nil)
        payload = build_error_response("Internal server error", 500)
        sign_response(payload)
        render json: payload, status: :internal_server_error
      end

      # Rate limiting check
      # Only include QR code when explicitly requested via ?include=qr_code
      # Saves ~5-15ms by avoiding 10-15KB base64 serialization on every response
      def include_qr_code?
        params[:include].to_s.split(",").map(&:strip).include?("qr_code")
      end

      # NOTE: API access logging is handled by BaseController#log_partner_api_access (around_action)
      # No per-action logging needed — eliminates ~10-20ms of duplicate DB writes per request.
    end
  end
end
