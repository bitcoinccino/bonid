# frozen_string_literal: true

class OauthController < ApplicationController
  include Rails.application.routes.url_helpers
  layout "citizen_auth"

  before_action :authenticate_citizen!, only: %i[consent decision]
  before_action :ensure_verified_bonid!, only: %i[consent decision]
  skip_forgery_protection only: %i[token userinfo]

  # Make helper methods available to views
  helper_method :visible_scopes, :scope_label, :scope_description, :scope_icon, :scope_color

  # ------------------------------------------------------------
  # STEP 1: Partner initiates OAuth request
  # ------------------------------------------------------------
  def authorize
    @partner = find_partner_from_params
    return render_error("Invalid or unknown partner") unless @partner

    # Validate and filter scopes using Partner model method
    # Support both: BonID's comma-separated "scopes" param and standard OAuth2 space-separated "scope" param
    raw_scopes = params[:scopes].presence || params[:scope].presence || ""
    @scopes = @partner.filter_scopes(raw_scopes.to_s.split(/[\s,]+/))

    # Validate redirect URI
    @redirect_uri = validate_redirect_uri(params[:redirect_uri])

    # Preserve partner's state parameter (for standard OAuth2 CSRF validation)
    # Only generate a new one if the partner didn't send one
    @state = params[:state].presence || SecureRandom.urlsafe_base64(32)

    # ================================================================
    # OpenID Connect `prompt` parameter support
    # - prompt=login  → Force re-authentication (sign out current session)
    # - prompt=consent → Always show consent screen, never auto-approve
    # - prompt=none   → Never show UI; fail if auth required
    # ================================================================
    @prompt = params[:prompt].to_s.downcase.strip

    # prompt=login → sign out citizen to force a fresh login on BonID
    if @prompt == "login" && current_citizen
      sign_out(:citizen)
    end

    pending_data = {
      partner_id: @partner.id,
      partner_slug: @partner.slug,
      scopes: @scopes,
      redirect_uri: @redirect_uri,
      state: @state,
      prompt: @prompt,
      created_at: Time.current.to_i
    }

    # Persist handoff context (session + cookie)
    store_pending_consent!(pending_data)

    # If citizen already logged in:
    if current_citizen
      # prompt=none → must return immediately (no UI allowed)
      # If we get here, citizen IS logged in, so continue to check grant

      # Must be verified to share
      unless current_citizen.identity_submissions.approved.exists?
        cleanup_pending_consent
        return redirect_to citizens_identity_submissions_path,
                           alert: "Please verify your BonID before sharing data with partners."
      end

      # ✅ If already has an ACTIVE grant that covers requested scopes,
      # skip consent and return directly to the partner.
      # UNLESS prompt=consent (force showing consent screen again)
      if @prompt != "consent" && (grant = active_grant_covering_scopes(current_citizen, @partner, @scopes))
        cleanup_pending_consent
        auth_code = generate_authorization_code(current_citizen, @partner, @redirect_uri)
        redirect_params = {
          grant_token: grant.grant_token,
          status: "approved",
          state: @state
        }
        redirect_params[:code] = auth_code if auth_code
        redirect_url = build_redirect_url(@redirect_uri, redirect_params)
        flash[:notice] = "You have already verified. You are now being redirected to #{@partner.name}."
        return redirect_to redirect_url, allow_other_host: true
      end

      # Otherwise show consent screen
      return redirect_to consent_oauth_index_path(partner_slug: @partner.slug)
    end

    # Not logged in → go through OTP sign-in
    redirect_to main_app.citizens_otp_sign_in_path(from_partner: @partner.slug)
  rescue SecurityError => e
    cleanup_pending_consent
    render_error(e.message)
  rescue => e
    Rails.logger.error("OAuth authorize failed: #{e.message}")
    cleanup_pending_consent
    render_error("Could not start authorization. Please try again.")
  end

  # ------------------------------------------------------------
  # STEP 2: Consent Screen
  # ------------------------------------------------------------
  def consent
    @current_user = current_citizen

    pending_data = retrieve_pending_consent
    unless pending_data
      return redirect_to root_path,
                         alert: "Consent session expired. Please try again from your partner."
    end

    if session_expired?(pending_data)
      cleanup_pending_consent
      return redirect_to root_path,
                         alert: "Consent session expired. Please try again from your partner."
    end

    @partner = Partner.find_by(id: pending_data[:partner_id])
    unless @partner
      cleanup_pending_consent
      return render_error("Invalid partner")
    end

    @scopes = Array(pending_data[:scopes]).compact
    @state  = pending_data[:state].presence || SecureRandom.urlsafe_base64(32)

    # Ensure state exists (important for CSRF/state validation later)
    session[:pending_consent] = pending_data.merge(state: @state)

    # Clean up temporary partner slug
    session.delete(:pending_partner_slug)

    # ✅ If already active grant covers scopes, auto-return to partner
    # UNLESS prompt=consent was set (force showing consent screen again)
    prompt = pending_data[:prompt].to_s
    if prompt != "consent" && (grant = active_grant_covering_scopes(@current_user, @partner, @scopes))
      redirect_uri = pending_data[:redirect_uri].presence || @partner.primary_redirect_uri || root_url
      cleanup_pending_consent

      auth_code = generate_authorization_code(@current_user, @partner, redirect_uri)
      redirect_params = {
        grant_token: grant.grant_token,
        status: "approved",
        state: @state
      }
      redirect_params[:code] = auth_code if auth_code
      redirect_url = build_redirect_url(redirect_uri, redirect_params)

      flash[:notice] = "You have already verified. You are now being redirected to #{@partner.name}."
      return redirect_to redirect_url, allow_other_host: true
    end

    # Detect scope upgrade: existing grant covers some but not all requested scopes
    existing_grant = @current_user&.consent_grants&.find_by(partner: @partner)
    if existing_grant&.active?
      already_granted = Array(existing_grant.granted_scopes.presence || existing_grant.requested_scopes).map(&:to_s)
      @new_scopes = @scopes.map(&:to_s) - already_granted
      @already_granted_scopes = already_granted & @scopes.map(&:to_s)
      @is_scope_upgrade = @new_scopes.any? && @already_granted_scopes.any?
    else
      @new_scopes = @scopes.map(&:to_s)
      @already_granted_scopes = []
      @is_scope_upgrade = false
    end

    # Citizen payload (for JSON consumers or UI)
    @citizen_data =
      if @current_user.present?
        OidcTokenService.new(citizen: @current_user, scopes: @scopes).payload
      else
        {}
      end

    respond_to do |format|
      format.html
      format.json
    end
  end

  # ------------------------------------------------------------
  # STEP 3: Decision (Approve/Deny)
  # ------------------------------------------------------------
  def decision
    citizen = current_citizen
    return render_error("Authentication required") unless citizen

    pending_data = retrieve_pending_consent
    return render_error("Consent session expired") unless pending_data

    unless valid_state?(pending_data, params[:state])
      cleanup_pending_consent
      return render_error("Invalid security token. Please try again.")
    end

    @partner = Partner.find_by(id: pending_data[:partner_id])
    unless @partner
      cleanup_pending_consent
      return render_error("Unknown partner")
    end

    @scopes = Array(pending_data[:scopes]).compact.presence || []
    redirect_uri = pending_data[:redirect_uri].presence || @partner.primary_redirect_uri

    cleanup_pending_consent

    # Create or update consent grant
    @grant = citizen.consent_grants.find_or_initialize_by(partner: @partner)
    @grant.requested_scopes = @scopes
    @grant.generate_grant_token if @grant.grant_token.blank?

    status =
      case params[:decision].to_s.downcase
      when "approve"
        # Granular consent: use citizen-selected scopes from toggle checkboxes
        selected_scopes = Array(params[:granted_scopes]).map(&:to_s).reject(&:blank?)

        # Security: only allow scopes that were actually requested by the partner
        allowed = selected_scopes & @scopes.map(&:to_s)
        allowed = @scopes.map(&:to_s) if allowed.empty? # fallback to all if none submitted

        # Always include openid if it was requested
        if @scopes.map(&:to_s).include?("openid") && !allowed.include?("openid")
          allowed << "openid"
        end

        @grant.grant!(scopes: allowed)
        @allowed_scopes = allowed
        "approved"
      else
        @grant.revoke!(reason: "Citizen denied consent")
        "denied"
      end

    # Build redirect params — include both standard OAuth2 `code` and BonID `grant_token`
    redirect_params = {
      state: pending_data[:state],
      grant_token: @grant.grant_token,
      status: status
    }

    # For approved decisions, generate a standard OAuth2 authorization code
    if status == "approved"
      auth_code = generate_authorization_code(citizen, @partner, redirect_uri)
      redirect_params[:code] = auth_code if auth_code
      # Include granted scopes so partner knows what was approved (graceful degradation)
      redirect_params[:granted_scopes] = @allowed_scopes.join(",")
    end

    redirect_url = build_redirect_url(redirect_uri, redirect_params)

    respond_to do |format|
      format.html { redirect_to redirect_url, allow_other_host: true }
      format.json do
        render json: {
          success: status == "approved",
          status: status,
          partner: { id: @partner.id, name: @partner.name },
          citizen: { bonid: citizen.bonid },
          grant_token: @grant.grant_token,
          granted_scopes: status == "approved" ? @allowed_scopes : [],
          code: redirect_params[:code],
          state: pending_data[:state],
          timestamp: Time.current.iso8601
        }, status: :ok
      end
    end
  end

  # ------------------------------------------------------------
  # STEP 4: Token Exchange (Standard OAuth2)
  # POST /oauth/token
  # Accepts: grant_type=authorization_code, code, client_id, client_secret, redirect_uri
  # ------------------------------------------------------------
  def token
    # Skip CSRF — this is a server-to-server POST
    unless params[:grant_type] == "authorization_code"
      return render json: { error: "unsupported_grant_type" }, status: :bad_request
    end

    # Extract client credentials from HTTP Basic Auth or form params
    client_id, client_secret = extract_client_credentials

    # Authenticate the client via client_id + client_secret
    oauth_app = OauthApplication.find_by(uid: client_id)
    unless oauth_app && oauth_app.authenticate(client_secret.to_s)
      return render json: { error: "invalid_client" }, status: :unauthorized
    end

    # Find and validate the authorization code
    auth_code = OauthAuthorizationCode.find_by_code(params[:code].to_s)
    unless auth_code
      return render json: { error: "invalid_grant", error_description: "Invalid or expired authorization code" }, status: :bad_request
    end

    # Verify the code belongs to this application
    unless auth_code.oauth_application_id == oauth_app.id
      return render json: { error: "invalid_grant" }, status: :bad_request
    end

    # Verify redirect_uri matches (compare base URIs without query params)
    if params[:redirect_uri].present? && auth_code.redirect_uri.present?
      sent_base = strip_query_params(params[:redirect_uri])
      stored_base = strip_query_params(auth_code.redirect_uri)
      unless sent_base == stored_base
        return render json: { error: "invalid_grant", error_description: "Redirect URI mismatch" }, status: :bad_request
      end
    end

    # Mark code as used (single-use)
    auth_code.mark_used!

    # Resolve citizen and scopes
    citizen = User.find(auth_code.user_id)
    grant = citizen.consent_grants.find_by(partner_id: oauth_app.partner_id)
    scope_list = Array(grant&.granted_scopes.presence || grant&.requested_scopes).map(&:to_s)
    scope_list = %w[openid profile email] if scope_list.empty?

    # Create access token (scopes is a PostgreSQL array column)
    access_token = OauthAccessToken.create!(
      partner_id: oauth_app.partner_id,
      citizen_id: citizen.id,
      scopes: scope_list,
      expires_at: 1.hour.from_now
    )

    render json: {
      access_token: access_token.token,
      token_type: "Bearer",
      expires_in: 3600,
      refresh_token: access_token.refresh_token,
      scope: scope_list.join(" ")
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "invalid_grant" }, status: :bad_request
  end

  # ------------------------------------------------------------
  # STEP 5: Userinfo (Standard OAuth2 / OIDC)
  # GET /oauth/userinfo
  # Requires: Authorization: Bearer <access_token>
  # ------------------------------------------------------------
  def userinfo
    token_value = request.headers["Authorization"].to_s.split.last
    access_token = OauthAccessToken.find_by(token: token_value)

    unless access_token&.active?
      return render json: { error: "Invalid or expired token" }, status: :unauthorized
    end

    citizen = access_token.citizen
    unless citizen
      return render json: { error: "Citizen not found" }, status: :not_found
    end

    # Double-check consent grant is still active (defense-in-depth)
    grant = citizen.consent_grants.find_by(partner_id: access_token.partner_id)
    unless grant&.active?
      access_token.revoke!
      return render json: { error: "Consent revoked", verified: false }, status: :unauthorized
    end

    # Build scope-aware payload using OidcTokenService
    payload = OidcTokenService.new(citizen: citizen, scopes: access_token.scopes).payload

    # Always include sub (required by OIDC)
    payload[:sub] = citizen.id
    payload[:verified] = true

    # Add photo_url if profile scope granted and photo attached
    if access_token.scopes.include?("profile") && citizen.respond_to?(:photo) && citizen.photo.attached?
      payload[:photo_url] = Rails.application.routes.url_helpers.rails_blob_url(
        citizen.photo, only_path: false, host: request.base_url
      )
    end

    # Include granted scopes for client reference
    payload[:scopes] = access_token.scopes

    render json: payload
  end

  private

  # ------------------------------------------------------------
  # Scope Helper Methods (Available to Views)
  # ------------------------------------------------------------

  SCOPE_DEFINITIONS = {
    "openid" => {
      hidden: true,
      label: "Basic Authentication",
      icon: "shield-keyhole-line",
      description: "Confirms your identity securely",
      color: "primary"
    },
    "profile" => {
      label: "Name & Photo",
      icon: "user-line",
      description: "Your full name, date of birth, and profile photo",
      color: "primary"
    },
    "email" => {
      label: "Email Address",
      icon: "mail-line",
      description: "Your verified email address",
      color: "info"
    },
    "phone" => {
      label: "Phone Number",
      icon: "phone-line",
      description: "Your verified phone number",
      color: "success"
    },
    "address" => {
      label: "Physical Address",
      icon: "map-pin-line",
      description: "Your residential address",
      color: "warning"
    },
    "physical" => {
      label: "Physical Profile",
      icon: "body-scan-line",
      description: "Your physical characteristics",
      color: "secondary"
    },
    "health" => {
      label: "Health Profile",
      icon: "heart-pulse-line",
      description: "Your health information and medical data",
      color: "danger"
    },
    "identity:verify" => {
      label: "Identity Verification",
      icon: "fingerprint-line",
      description: "Verify your BonID status",
      color: "primary"
    },
    "crime:status" => {
      label: "Crime Status Check",
      icon: "shield-user-line",
      description: "Check if you have any criminal records",
      color: "danger"
    }
  }.freeze

  def visible_scopes(scopes)
    Array(scopes).reject { |scope| SCOPE_DEFINITIONS.dig(scope.to_s, :hidden) }
  end

  def scope_definition(scope)
    SCOPE_DEFINITIONS[scope.to_s] || {
      label: scope.to_s.humanize,
      icon: "database-line",
      description: "Access to #{scope}",
      color: "secondary"
    }
  end

  def scope_label(scope) = scope_definition(scope)[:label]
  def scope_icon(scope) = scope_definition(scope)[:icon]
  def scope_description(scope) = scope_definition(scope)[:description]
  def scope_color(scope) = scope_definition(scope)[:color]

  # ------------------------------------------------------------
  # Validation Methods
  # ------------------------------------------------------------

  def validate_redirect_uri(uri)
    # If no URI provided, use the partner's default
    if uri.blank?
      fallback = @partner.primary_redirect_uri
      if fallback.blank?
        Rails.logger.error("OAuth blocked: partner #{@partner.slug} has no registered redirect URIs")
        raise SecurityError, "This partner has no registered redirect URI. Contact the BonID admin to configure one."
      end
      return fallback
    end

    normalized_uri = uri.to_s.strip

    unless @partner.valid_redirect_uri?(normalized_uri)
      Rails.logger.warn("Invalid redirect_uri attempt: #{normalized_uri} for partner #{@partner.slug}")
      raise SecurityError, "Invalid redirect_uri for this partner"
    end

    normalized_uri
  end

  def valid_state?(pending_data, provided_state)
    return false if pending_data[:state].blank? || provided_state.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      pending_data[:state].to_s,
      provided_state.to_s
    )
  end

  # ------------------------------------------------------------
  # Consent Grant Helpers
  # ------------------------------------------------------------

  def active_grant_covering_scopes(citizen, partner, requested_scopes)
    return nil if citizen.blank? || partner.blank?

    grant = citizen.consent_grants.find_by(partner: partner)

    unless grant
      Rails.logger.info "[OAuth] No consent grant found for citizen #{citizen.id} + partner #{partner.slug}"
      return nil
    end

    unless grant.active?
      Rails.logger.info "[OAuth] Grant ##{grant.id} exists but not active (status=#{grant.status}, expires_at=#{grant.expires_at})"
      return nil
    end

    granted = Array(grant.granted_scopes.presence || grant.requested_scopes).map(&:to_s)
    needed  = Array(requested_scopes).map(&:to_s)
    missing = needed - granted

    if missing.any?
      Rails.logger.info "[OAuth] Grant ##{grant.id} missing scopes: #{missing.join(', ')} (has: #{granted.join(', ')})"
      return nil
    end

    Rails.logger.info "[OAuth] Auto-skipping consent for citizen #{citizen.id} + partner #{partner.slug} (grant ##{grant.id})"
    grant
  rescue => e
    Rails.logger.warn("Grant coverage check failed: #{e.message}")
    nil
  end

  # ------------------------------------------------------------
  # Authorization Code Generation
  # ------------------------------------------------------------

  def generate_authorization_code(citizen, partner, redirect_uri)
    oauth_app = OauthApplication.find_by(partner_id: partner.id)
    return nil unless oauth_app

    auth_code = oauth_app.oauth_authorization_codes.new(redirect_uri: redirect_uri)
    auth_code.user_id = citizen.id
    auth_code.save!
    auth_code.plain_code
  rescue => e
    Rails.logger.error("Failed to generate OAuth authorization code: #{e.message}")
    nil
  end

  # ------------------------------------------------------------
  # Session Management
  # ------------------------------------------------------------

  def store_pending_consent!(pending_data)
    session[:pending_consent] = pending_data
    session[:pending_partner_slug] = pending_data[:partner_slug]

    cookies.encrypted[:pending_consent] = {
      value: pending_data.to_json,
      expires: 30.minutes.from_now,
      httponly: true,
      secure: Rails.application.config.force_ssl
    }
  end

  def retrieve_pending_consent
    pending_data = session[:pending_consent]

    # ✅ Cookie fallback (because OTP + redirects can lose session context)
    if pending_data.blank? && cookies.encrypted[:pending_consent].present?
      pending_data = JSON.parse(cookies.encrypted[:pending_consent]) rescue nil
      session[:pending_consent] = pending_data if pending_data.present?
    end

    # Try to reconstruct from partner_slug if still missing
    pending_data = reconstruct_from_partner_slug if pending_data.blank?

    return nil if pending_data.blank?

    pending_data = pending_data.with_indifferent_access if pending_data.respond_to?(:with_indifferent_access)
    return nil unless pending_data[:partner_id].present?

    pending_data
  end

  def reconstruct_from_partner_slug
    slug = params[:partner_slug] || session[:pending_partner_slug]
    return nil if slug.blank?

    partner = Partner.find_by(slug: slug)
    return nil unless partner

    state = SecureRandom.urlsafe_base64(32)

    pending_data = {
      partner_id: partner.id,
      partner_slug: partner.slug,
      scopes: %w[openid profile email],
      redirect_uri: partner.primary_redirect_uri.presence || root_url,
      state: state,
      created_at: Time.current.to_i
    }

    store_pending_consent!(pending_data)
    pending_data
  end

  def session_expired?(pending_data)
    return false unless pending_data[:created_at].present?

    created_at = Time.at(pending_data[:created_at].to_i)
    created_at < 30.minutes.ago
  rescue ArgumentError, TypeError
    true
  end

  def cleanup_pending_consent
    session.delete(:pending_consent)
    session.delete(:pending_partner_slug)
    cookies.encrypted[:pending_consent] = nil
  end

  # ------------------------------------------------------------
  # Helper Methods
  # ------------------------------------------------------------

  # Extract client credentials from HTTP Basic Auth header or form params
  # OmniAuth may send them either way depending on auth_scheme config
  def extract_client_credentials
    auth_header = request.headers["Authorization"].to_s
    if auth_header.start_with?("Basic ")
      decoded = Base64.decode64(auth_header.sub("Basic ", ""))
      client_id, client_secret = decoded.split(":", 2)
      [client_id, client_secret]
    else
      [params[:client_id], params[:client_secret]]
    end
  end

  # Strip query params from a URI for comparison
  def strip_query_params(uri_string)
    uri = URI.parse(uri_string.to_s)
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    uri_string.to_s.split("?").first
  end

  def build_redirect_url(base_uri, params)
    uri = URI.parse(base_uri)
    existing_params = Rack::Utils.parse_nested_query(uri.query.to_s)
    merged_params = existing_params.merge(params.stringify_keys)
    uri.query = merged_params.to_query
    uri.to_s
  end

  def ensure_verified_bonid!
    unless current_citizen&.identity_submissions&.approved&.exists?
      flash[:alert] = "You must verify your BonID before authorizing access."
      redirect_to citizens_identity_submissions_path
    end
  end

  def find_partner_from_params
    # 1. Try slug (BonID's custom param)
    if params[:partner].present?
      return Partner.find_by(slug: params[:partner])
    end

    # 2. Try client_id (standard OAuth2 param) → lookup via OauthApplication
    if params[:client_id].present?
      app = OauthApplication.find_by(uid: params[:client_id])
      return app&.partner
    end

    nil
  end

  def render_error(msg)
    Rails.logger.warn("OAuth Error: #{msg} - IP: #{request.remote_ip}")

    render inline: <<~HTML, content_type: "text/html", status: :unprocessable_entity
      <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>BonID - Error</title>
        </head>
        <body style="font-family:Montserrat,Arial,sans-serif;text-align:center;padding:60px;background:#f8f9fa;color:#00209F;">
          <h1 style="font-size:2.5rem;">⚠️ #{ERB::Util.html_escape(msg)}</h1>
          <p style="margin:30px 0;">
            <a href="/" style="color:#00209F;text-decoration:underline;font-weight:600;">← Return to BonID</a>
          </p>
        </body>
      </html>
    HTML
  end
end
