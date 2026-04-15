# app/services/bonid_notifier.rb
require "net/http"

class BonidNotifier
  MAX_RETRIES = 3
  BASE_DELAY  = 2 # seconds

  # GDPR erasure webhooks get extended retries (consent.revoked)
  GDPR_MAX_RETRIES = 10
  GDPR_RETRY_SCHEDULE = [
    5.seconds,      # attempt 2
    30.seconds,     # attempt 3
    2.minutes,      # attempt 4
    10.minutes,     # attempt 5
    30.minutes,     # attempt 6
    1.hour,         # attempt 7
    3.hours,        # attempt 8
    6.hours,        # attempt 9
    12.hours        # attempt 10
  ].freeze

  class << self
    # ===========================================================
    # Generic partner webhook (existing ApiWebhookEvent-based)
    # ===========================================================
    def notify_partner(partner, event, attempt: 1)
      return unless partner&.webhook_enabled?

      body = build_payload(event).to_json
      signature = partner.sign_webhook_payload(body)

      headers = {
        "Content-Type"      => "application/json",
        "X-BonID-Event"     => event.event_type,
        "X-BonID-Signature" => signature,
        "X-BonID-Timestamp" => Time.current.to_i.to_s
      }

      uri = URI(partner.webhook_url)
      response = send_request(uri, body, headers)

      if response.is_a?(Net::HTTPSuccess)
        log_delivery(partner, event, response, success: true)
        Rails.logger.info("[BonidNotifier] Delivered successfully to #{partner.name}")
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    rescue => e
      Rails.logger.warn("[BonidNotifier] Attempt #{attempt} failed for #{partner&.name}: #{e.message}")
      log_delivery(partner, event, e, success: false)

      # Exponential backoff retry
      if attempt < MAX_RETRIES
        delay = BASE_DELAY**attempt
        Rails.logger.info("[BonidNotifier] Retrying in #{delay}s (attempt #{attempt + 1})")
        WebhookRetryJob.set(wait: delay.seconds).perform_later(partner.id, event.id, attempt + 1)
      else
        Rails.logger.error("[BonidNotifier] Max retries reached for #{partner&.name}")
      end
    end

    # ===========================================================
    # Consent lifecycle webhook (revoked, restored, approved, bonid.changed)
    # ===========================================================
    def notify_consent_change(consent_grant, event_type, attempt: 1)
      partner = consent_grant.partner
      return unless partner&.webhook_enabled?

      citizen = consent_grant.citizen
      return unless citizen&.bonid.present?

      payload = {
        event:        event_type,
        bonid:        citizen.bonid,
        partner_id:   partner.id,
        partner_slug: partner.slug,
        consent_id:   consent_grant.id,
        scopes:       consent_grant.granted_scopes,
        timestamp:    Time.current.iso8601
      }

      # For BonID change events, include the old BonID from aliases
      if event_type == "bonid.changed"
        alias_record = citizen.bonid_aliases.order(created_at: :desc).first
        payload[:previous_bonid] = alias_record&.old_bonid
      end

      # GDPR Article 17 — data erasure request on consent revocation
      if event_type == "consent.revoked"
        payload[:data_erasure] = {
          requested: true,
          reason: consent_grant.change_reason || "citizen_revoked_consent",
          gdpr_article: "Article 17 — Right to Erasure",
          obligation: "Delete or anonymize all personal data obtained via BonID consent within 30 days.",
          revoked_at: consent_grant.revoked_at&.iso8601,
          deadline: (consent_grant.revoked_at + 30.days).iso8601
        }
      end

      payload_json = payload.to_json
      signature = partner.sign_webhook_payload(payload_json)

      headers = {
        "Content-Type"      => "application/json",
        "X-BonID-Event"     => event_type,
        "X-BonID-Signature" => signature,
        "X-BonID-Timestamp" => Time.current.to_i.to_s
      }

      # Create webhook event record for audit
      webhook_event = ApiWebhookEvent.create!(
        partner:        partner,
        event_type:     event_type,
        bonid:          citizen.bonid,
        payload:        payload,
        retry_attempts: [attempt - 1, 0].max,
        direction:      "outbound",
        status:         "pending"
      )

      response = send_request(URI(partner.webhook_url), payload_json, headers)

      if response.is_a?(Net::HTTPSuccess)
        webhook_event.update!(status: "delivered", delivered_at: Time.current)
        Rails.logger.info("[BonidNotifier] Consent webhook '#{event_type}' delivered to #{partner.name}")
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    rescue => e
      Rails.logger.warn("[BonidNotifier] Consent webhook attempt #{attempt} failed for #{partner&.name}: #{e.message}")

      if defined?(webhook_event) && webhook_event&.persisted?
        webhook_event.update!(
          status: "failed",
          retry_attempts: attempt,
          payload: webhook_event.payload.merge("error" => e.message, "last_attempt_at" => Time.current.iso8601)
        )
      end

      # GDPR-critical events (consent.revoked) get extended retry schedule
      is_gdpr = event_type == "consent.revoked"
      max = is_gdpr ? GDPR_MAX_RETRIES : MAX_RETRIES

      if attempt < max
        delay = if is_gdpr
                  GDPR_RETRY_SCHEDULE[attempt - 1] || 12.hours
                else
                  BASE_DELAY**attempt
                end
        Rails.logger.info("[BonidNotifier] Retrying consent webhook in #{delay}s (attempt #{attempt + 1}/#{max}, gdpr=#{is_gdpr})")
        if defined?(webhook_event) && webhook_event&.persisted?
          WebhookRetryJob.set(wait: delay).perform_later(partner.id, webhook_event.id, attempt + 1)
        end
      else
        # Dead letter — all retries exhausted
        if defined?(webhook_event) && webhook_event&.persisted?
          webhook_event.update!(status: "dead_letter")
        end
        Rails.logger.error("[BonidNotifier] DEAD LETTER: #{event_type} webhook to #{partner&.name} failed after #{max} attempts. Manual intervention required.")

        # Notify BonID admin of undelivered GDPR erasure
        if is_gdpr
          PartnerAuditLog.create!(
            partner: partner,
            event: "gdpr_erasure_delivery_failed",
            details: "GDPR erasure webhook failed after #{max} attempts. Manual follow-up required.",
            metadata: { webhook_event_id: webhook_event&.id, citizen_bonid: citizen&.bonid }
          )
        end
      end
    end

    # ===========================================================
    # Transaction Consent callback (per-transaction URL)
    # ===========================================================
    def notify_transaction_consent(consent, attempt: 1)
      return unless consent.callback_url.present?

      uri = URI(consent.callback_url)
      headers = {
        "Content-Type" => "application/json",
        "X-BonID-Event" => "transaction_consent.#{consent.status}"
      }

      payload = {
        consent_token: consent.consent_token,
        bonid: consent.citizen.bonid,
        transaction_type: consent.transaction_type,
        status: consent.status,
        reference_id: consent.reference_id,
        amount: consent.amount&.to_s,
        currency: consent.currency,
        signature: consent.signature,
        decided_at: consent.decided_at&.iso8601,
        expires_at: consent.expires_at.iso8601,
        timestamp: Time.current.iso8601
      }

      # Include biometric verification proof for approved consents
      if consent.status == "approved" && consent.biometric_verified_at.present?
        face_data = consent.metadata&.dig("face_comparison")
        payload[:biometric_verification] = {
          liveness_passed: true,
          liveness_confidence: consent.liveness_confidence&.to_f,
          face_matched: face_data.present? && face_data["similarity"].to_f >= FaceMatchService::SIMILARITY_THRESHOLD,
          face_similarity: face_data&.dig("similarity")&.to_f,
          compared_against: "bonid_selfie",
          threshold: FaceMatchService::SIMILARITY_THRESHOLD,
          verified_at: consent.biometric_verified_at&.iso8601
        }.compact
      end

      response = send_request(uri, payload.to_json, headers)

      if response.is_a?(Net::HTTPSuccess)
        Rails.logger.info("[BonidNotifier] Transaction consent callback delivered to #{uri.host}")
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    rescue => e
      Rails.logger.warn("[BonidNotifier] Transaction consent callback attempt #{attempt} failed: #{e.message}")

      if attempt < MAX_RETRIES
        delay = BASE_DELAY**attempt
        Rails.logger.info("[BonidNotifier] Retrying transaction consent callback in #{delay}s")
        begin
          TransactionConsentCallbackRetryJob.set(wait: delay.seconds)
            .perform_later(consent.id, attempt + 1)
        rescue NotImplementedError
          Rails.logger.info("[BonidNotifier] Retry skipped (no async adapter)")
        end
      else
        Rails.logger.error("[BonidNotifier] Max retries for transaction consent #{consent.consent_token}")
      end
    end

    private

    def build_payload(event)
      {
        bonid: event.payload["bonid"],
        event_type: event.event_type,
        status: event.payload["status"],
        timestamp: Time.current.iso8601,
        payload: event.payload
      }
    end

    def send_request(uri, body, headers)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      verify_mode: ssl_verify_mode) do |http|
        http.open_timeout = 10
        http.read_timeout = 15
        req = Net::HTTP::Post.new(uri, headers)
        req.body = body
        http.request(req)
      end
    end

    def ssl_verify_mode
      if Rails.env.development? || Rails.env.test?
        OpenSSL::SSL::VERIFY_NONE
      else
        OpenSSL::SSL::VERIFY_PEER
      end
    end

    def log_delivery(partner, event, result, success:)
      ApiWebhookEvent.create!(
        partner:        partner,
        event_type:     "#{event.event_type}_delivery",
        bonid:          event.payload["bonid"] || "unknown",
        direction:      "outbound",
        status:         success ? "delivered" : "failed",
        delivered_at:   success ? Time.current : nil,
        retry_attempts: 0,
        payload: {
          source_event_id: event.id,
          bonid: event.payload["bonid"],
          result: format_result(result),
          success: success
        }
      )
    end

    def format_result(result)
      if result.is_a?(Net::HTTPResponse)
        { code: result.code, body: result.body, success: result.is_a?(Net::HTTPSuccess) }
      else
        { error: result.to_s }
      end
    end
  end
end
