# frozen_string_literal: true

module Api
  module V1
    class ConsentsController < ActionController::API
      # Stateless controller — no Devise or portal auth
      protect_from_forgery with: :null_session if respond_to?(:protect_from_forgery)

      # ======================================================
      # POST /api/v1/request_consent  (Partner-triggered)
      # ======================================================
      def create
        partner = find_partner_by_api_key(extract_partner_key)
        return render json: { error: "Unauthorized partner" }, status: :unauthorized unless partner

        citizen = User.find_by(bonid: params[:bonid])
        return render json: { error: "Citizen not found" }, status: :not_found unless citizen

        scopes = Array(params[:scopes]).map(&:to_s)
        return render json: { error: "Missing scopes" }, status: :unprocessable_entity if scopes.empty?

        grant = ConsentGrant.create!(
          citizen: citizen,
          partner: partner,
          requested_scopes: scopes,
          requested_at: Time.current,
          metadata: {
            ip: request.remote_ip,
            ua: request.user_agent
          }
        )

        Citizens::ConsentMailer.with(grant: grant).request_notification.deliver_later

        render json: {
          message: "Consent request created successfully",
          grant_token: grant.grant_token,
          citizen: citizen.slice(:id, :first_name, :last_name, :bonid),
          partner: partner.slice(:id, :name, :sector),
          scopes: scopes
        }, status: :ok
      rescue => e
        Rails.logger.error("[Consent#create] #{e.class}: #{e.message}")
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      # ======================================================
      # GET /api/v1/citizen/approve_consent  (Citizen flow)
      # ======================================================
      def approve
        token    = params[:grant_token].to_s.strip
        decision = params[:decision].to_s.downcase.presence || "approve"
        scopes   = Array(params[:scopes])

        grant = ConsentGrant.find_by(grant_token: token)
        return render_html_error("Invalid or expired token") unless grant

        case decision
        when "approve"
          grant.grant!(scopes: scopes.presence || grant.requested_scopes)
          Citizens::ConsentMailer.with(grant: grant).approval_confirmation.deliver_later
          render_html_success(grant, "Consent Approved ✅")

        when "reject", "deny"
          grant.revoke!
          Citizens::ConsentMailer.with(grant: grant).denial_notification.deliver_later
          render_html_error("Consent Rejected ❌")

        else
          render_html_error("Invalid decision")
        end
      rescue => e
        Rails.logger.error("[Consent#approve] #{e.class}: #{e.message}")
        render_html_error("Internal error: #{e.message}")
      end

      private

      # Extract API key from header (Partner)
      def extract_partner_key
        request.headers["X-Partner-Api-Key"].presence
      end

      # SHA256 fast path + BCrypt fallback (matches base_controller pattern)
      def find_partner_by_api_key(api_key)
        return nil if api_key.blank?

        sha_digest = Digest::SHA256.hexdigest(api_key)
        partner = Partner.find_by(api_key_digest: sha_digest)

        if partner.nil?
          partner = Partner.where.not(api_key_digest: nil).detect do |p|
            digest = p.api_key_digest.to_s
            next false if digest.blank?
            next false unless digest.start_with?("$2")

            begin
              BCrypt::Password.new(digest).is_password?(api_key)
            rescue BCrypt::Errors::InvalidHash
              false
            end
          end
        end

        partner
      end

      def render_html_success(grant, title)
        html = <<~HTML
          <html><body style='font-family:Montserrat,Arial;text-align:center;padding:50px;background:#f9fafb;color:#00209F'>
            <h1>#{title}</h1>
            <p>Your consent for <strong>#{grant.partner.name}</strong> has been approved.</p>
            <p>Scopes: #{grant.scopes.join(', ')}</p>
            <p><a href='https://bonid.ht' style='color:#00209F;text-decoration:none;font-weight:600;'>Return to BonID</a></p>
          </body></html>
        HTML
        render inline: html, content_type: "text/html"
      end

      def render_html_error(message)
        html = <<~HTML
          <html><body style='font-family:Montserrat,Arial;text-align:center;padding:50px;background:#fff;color:#E53E3E'>
            <h1>⚠️ #{message}</h1>
            <p><a href='https://bonid.ht' style='color:#00209F;text-decoration:none;font-weight:600;'>Return to BonID</a></p>
          </body></html>
        HTML
        render inline: html, content_type: "text/html", status: :unprocessable_entity
      end
    end
  end
end
