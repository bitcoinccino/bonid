# app/services/bonid_lookup_service.rb
class BonidLookupService
  Result = Struct.new(
    :success?, :submission, :user, :visitor, :redirect_to, :error, :status,
    keyword_init: true
  )

  def initialize(params, officer, url_helpers: Rails.application.routes.url_helpers, request: nil)
    @params = params
    @officer = officer
    @url_helpers = url_helpers
    @request = request
  end

  def perform
    bonid       = @params[:bonid]&.strip
    timestamp   = @params[:timestamp] || @params[:verification_token]
    signature   = @params[:signature]
    partner_slug = extract_partner_slug

    Rails.logger.info("[BonidLookupService#perform] bonid=#{bonid}, timestamp=#{timestamp}, signature=#{signature}, partner_slug=#{partner_slug}")

    return fail_with("Missing BonID", bonid: bonid, status: :invalid_format) if bonid.blank?

    # Security check: Prevent officers from looking up their own BonID
    if self_lookup?(bonid)
      Rails.logger.warn("[BonidLookupService] Officer #{@officer&.id} attempted self-lookup for BonID: #{bonid}")
      return fail_with("You cannot verify your own BonID", bonid: bonid, status: :self_lookup_prohibited)
    end

    # Ed25519 v2 QR payload — asymmetric signature verification (most secure)
    if @params["v"].to_i == 2 && @params["sig"].present?
      return verify_ed25519_lookup(@params, partner_slug)
    end

    # Legacy HMAC QR scan with signature verification
    if timestamp.present? && signature.present?
      return verify_signed_lookup(bonid, timestamp, signature, partner_slug)
    end

    # NEW: Simplified 6-7 digit lookup (searches both citizens and tourists)
    if digit_only_format?(bonid)
      return digit_lookup(bonid)
    end

    # Check if this is a full BonTouris (visitor) lookup - starts with T-
    if visitor_bonid_format?(bonid)
      return visitor_lookup(bonid)
    end

    # Check if this is a BonTouris suffix lookup (P-123456 - 6 digits for passport)
    if visitor_suffix_format?(bonid)
      return visitor_suffix_lookup(bonid)
    end

    # Check if this is a citizen suffix lookup (P-XXXX-XXX format)
    if suffix_format?(bonid)
      return suffix_lookup(bonid)
    end

    # Full BonID manual lookup (citizen)
    manual_lookup(bonid)
  end

  # Check if input is a short-form lookup (6 or 7 alphanumeric chars, no P- prefix)
  # BonID suffixes contain hex checksum chars (0-9, A-F), e.g. "3344EC"
  def digit_only_format?(input)
    return false if input.blank?
    input.match?(/^[A-Z0-9]{6}$/i)
  end

  # Unified digit lookup - searches citizens first, then tourists
  # Accepts 6 or 7 digits
  def digit_lookup(digits)
    Rails.logger.info("[BonidLookupService#digit_lookup] Searching for digits: #{digits}")

    # Try citizen lookup first (BonID ends with P-XXXX-XXX pattern - 7 digits total)
    citizen_result = find_citizen_by_digits(digits)
    return citizen_result if citizen_result&.success?

    # Try tourist lookup (BonTouris ends with P-NNNNNN - exactly 6 digits)
    tourist_result = find_tourist_by_digits(digits)
    return tourist_result if tourist_result&.success?

    # Neither found
    fail_with("No matching BonID or BonTouris found for these digits", bonid: digits, status: :not_found)
  end

  # Find citizen by last 6-7 characters of BonID suffix
  # BonID citizen format: JM-1968-M-OUEST-P-NNNN-CCC (4 id digits + 3 hex checksum)
  # Example: entering "3344EC4" (7 chars) should match P-3344-EC4
  # Example: entering "3344EC" (6 chars) should also find it via flexible search
  def find_citizen_by_digits(digits)
    digits = digits.upcase
    Rails.logger.info("[BonidLookupService#find_citizen_by_digits] Looking for citizen with suffix: #{digits}")

    patterns = []

    if digits.length == 6
      # BonID has two possible formats:
      #   1. No dash before checksum: MB-1968-M-OU-P8697XDS → ends with "697XDS"
      #   2. Dash before checksum:    MB-1968-M-OU-P8697-XDS → ends with "697-XDS"
      #
      # User enters last 3 id digits + 3 checksum chars (e.g., "697XDS")
      # We search both patterns to handle either BonID format.
      id_part = digits[0..2]       # "697"
      checksum_part = digits[3..5] # "XDS"

      patterns << "%#{digits}"                     # no-dash format: %697XDS
      patterns << "%#{id_part}-#{checksum_part}"   # dash format:    %697-XDS

      Rails.logger.info("[BonidLookupService#find_citizen_by_digits] Trying patterns: %#{digits}, %#{id_part}-#{checksum_part}")
    end

    # Build the query with all patterns
    return nil if patterns.empty?

    conditions = patterns.map { "bonid LIKE ?" }.join(" OR ")
    submission = IdentitySubmission
      .where(status: :approved)
      .where(conditions, *patterns)
      .order(verified_at: :desc)
      .first

    if submission
      Rails.logger.info("[BonidLookupService#find_citizen_by_digits] Found submission: #{submission.id}, bonid: #{submission.bonid}")
    else
      Rails.logger.info("[BonidLookupService#find_citizen_by_digits] No citizen found")
    end

    return nil unless submission
    return fail_with("BonID has expired", bonid: digits, status: :expired) if submission.expires_at&.past?

    user = submission.user
    ensure_user_address(user)
    log_six_digit_lookup(submission, digits, "citizen")

    Result.new(
      success?: true,
      submission: submission,
      user: user,
      visitor: nil,
      redirect_to: officer_redirect_path(submission),
      status: :suffix_lookup_pending_confirmation
    )
  end

  # Find tourist by last 6 digits
  # BonTouris format: T-JM-1990-M-US-P-NNNNNN (ends with P- followed by 6 passport digits)
  def find_tourist_by_digits(digits)
    Rails.logger.info("[BonidLookupService#find_tourist_by_digits] Looking for tourist with digits: #{digits}")

    # BonTouris format ends with P-NNNNNN (exactly 6 digits)
    formatted = "P-#{digits}"

    visitor = VisitorSubmission
      .where(status: :approved)
      .where("bonid LIKE ?", "%-#{formatted}")
      .order(updated_at: :desc)
      .first

    if visitor
      Rails.logger.info("[BonidLookupService#find_tourist_by_digits] Found visitor: #{visitor.id}, bonid: #{visitor.bonid}")
    else
      Rails.logger.info("[BonidLookupService#find_tourist_by_digits] No tourist found")
    end

    return nil unless visitor

    log_six_digit_lookup_visitor(visitor, digits)

    Result.new(
      success?: true,
      submission: nil,
      user: nil,
      visitor: visitor,
      redirect_to: nil,
      status: :visitor_verified
    )
  end

  # Check if input is a BonTouris (visitor) BonID format: T-XX-YYYY-G-CC-P-NNNNNN
  def visitor_bonid_format?(input)
    return false if input.blank?
    input.upcase.start_with?("T-")
  end

  # Lookup visitor/tourist by BonTouris ID
  def visitor_lookup(bonid)
    Rails.logger.info("[BonidLookupService#visitor_lookup] Searching for visitor: #{bonid}")

    visitor = VisitorSubmission.find_by(bonid: bonid.upcase, status: :approved)
    return fail_with("BonTouris ID not found", bonid: bonid, status: :not_found) unless visitor

    log_visitor_lookup(visitor, bonid)

    Result.new(
      success?: true,
      submission: nil,
      user: nil,
      visitor: visitor,
      redirect_to: nil,
      status: :visitor_verified
    )
  end

  # Check if input is a BonTouris suffix: P-NNNNNN (P- followed by exactly 6 digits)
  # This is the passport number portion of the BonTouris ID
  def visitor_suffix_format?(input)
    return false if input.blank?
    # BonTouris suffix: P-123456 (exactly 6 digits after P-)
    input.match?(/^P-\d{6}$/i)
  end

  # Lookup visitor/tourist by BonTouris suffix (P-123456)
  def visitor_suffix_lookup(suffix)
    normalized = suffix.upcase
    Rails.logger.info("[BonidLookupService#visitor_suffix_lookup] Searching for suffix: #{normalized}")

    # Find visitors where bonid ends with this suffix
    visitor = VisitorSubmission
      .where(status: :approved)
      .where("bonid LIKE ?", "%-#{normalized}")
      .order(updated_at: :desc)
      .first

    return fail_with("No matching BonTouris found for suffix", bonid: suffix, status: :not_found) unless visitor

    log_visitor_lookup(visitor, suffix)

    Result.new(
      success?: true,
      submission: nil,
      user: nil,
      visitor: visitor,
      redirect_to: nil,
      status: :visitor_verified
    )
  end

  # Check if input matches citizen suffix format: P-XXXX-XXX or XXXX-XXX
  def suffix_format?(input)
    return false if input.blank?
    # Matches: P-1234-567 or 1234-567
    input.match?(/^[A-Z]?-?\d{4}-\d{2,3}$/i)
  end

  # Lookup by BonID suffix (last 2-3 segments)
  def suffix_lookup(suffix)
    normalized = normalize_suffix(suffix)
    Rails.logger.info("[BonidLookupService#suffix_lookup] Searching for suffix: #{normalized}")

    # Find submissions where bonid ends with this suffix
    submission = IdentitySubmission
      .where(status: :approved)
      .where("bonid LIKE ?", "%-#{normalized}")
      .order(verified_at: :desc)
      .first

    return fail_with("No matching BonID found for suffix", bonid: suffix, status: :not_found) unless submission
    return fail_with("BonID has expired", bonid: suffix, status: :expired) if submission.expires_at&.past?

    user = submission.user
    ensure_user_address(user)
    log_suffix_lookup(submission, suffix)

    Result.new(
      success?: true,
      submission: submission,
      user: user,
      visitor: nil,
      redirect_to: officer_redirect_path(submission),
      status: :suffix_lookup_pending_confirmation
    )
  end

  # Normalize suffix input to consistent format
  def normalize_suffix(suffix)
    # Remove leading letter and dash if present, ensure uppercase
    cleaned = suffix.strip.upcase
    # If format is "1234-567", prepend "P-"
    if cleaned.match?(/^\d{4}-\d{2,3}$/)
      "P-#{cleaned}"
    else
      cleaned
    end
  end

  private

  # Check if officer is trying to look up their own BonID
  def self_lookup?(bonid)
    return false unless @officer&.user_id.present?

    # Check full BonID match
    officer_submission = IdentitySubmission.find_by(user_id: @officer.user_id, status: :approved)
    return false unless officer_submission

    officer_bonid = officer_submission.bonid
    return true if officer_bonid&.casecmp?(bonid)

    # Check suffix match (last 2-3 segments like P2334-217)
    if suffix_format?(bonid)
      normalized_suffix = normalize_suffix(bonid)
      return officer_bonid&.end_with?("-#{normalized_suffix}")
    end

    # Check 6-digit format match
    if digit_only_format?(bonid)
      # New format: DV-1989-M-SE-P8697XDS — last segment is P8697XDS, extract last 6 chars
      officer_suffix = officer_bonid&.split("-")&.last&.slice(-6..)
      return officer_suffix == bonid if officer_suffix
    end

    false
  end

  def manual_lookup(bonid)
    # Full BonID format: DV-1989-M-SE-P8697XDS (entity + 4 digits + 3 char checksum, no dashes)
    unless bonid.match?(/^[A-Z]{2}-\d{4}-[A-Z]-[A-Z]+-[A-Z]\d{4}[A-Z0-9]{3}$/i)
      return fail_with("Invalid BonID format", bonid: bonid, status: :invalid_format)
    end

    submission = IdentitySubmission.find_by(bonid: bonid, status: :approved)
    return fail_with("BonID not found", bonid: bonid, status: :not_found) unless submission
    return fail_with("BonID has expired", bonid: bonid, status: :expired) if submission.expires_at&.past?

    user = submission.user
    ensure_user_address(user)
    log_manual_lookup(submission, bonid)

    Result.new(
      success?: true,
      submission: submission,
      user: user,
      visitor: nil,
      redirect_to: officer_redirect_path(submission),
      status: :manual_lookup
    )
  end

  # Ed25519 v2 verification — asymmetric, no shared secret needed.
  def verify_ed25519_lookup(payload, partner_slug)
    Rails.logger.info("[BonidLookupService#verify_ed25519] Verifying Ed25519 v2 payload for sub=#{payload['sub']}")
    result = BonidQrSigner.verify(payload)
    Rails.logger.info("[BonidLookupService#verify_ed25519] Verification result: #{result}")

    case result
    when :invalid_payload
      return fail_with("Invalid QR payload", bonid: payload["sub"], status: :invalid_format)
    when :invalid_signature
      return fail_with("Invalid or tampered QR signature", bonid: payload["sub"], status: :invalid_format)
    when :expired
      return fail_with("QR code has expired", bonid: payload["sub"], status: :expired_or_not_found)
    end

    bonid_value = payload["sub"]
    submission = IdentitySubmission.find_by(bonid: bonid_value, status: :approved)
    return fail_with("BonID not found", bonid: bonid_value, status: :not_found) unless submission
    return fail_with("BonID has expired", bonid: bonid_value, status: :expired) if submission.expires_at&.past?

    user = submission.user
    ensure_user_address(user)
    log_scan(submission, partner_slug)

    Result.new(
      success?: true,
      submission: submission,
      user: user,
      visitor: nil,
      redirect_to: officer_redirect_path(submission),
      status: :success
    )
  end

  # DEPRECATED: Legacy HMAC verification — kept for backward compat during v1→v2 migration.
  def verify_signed_lookup(bonid, timestamp, signature, partner_slug)
    return fail_with("Invalid or tampered QR signature", bonid: bonid, status: :invalid_format) unless verify_signature(bonid, timestamp, signature)

    begin
      time_diff = (Time.now.to_i - timestamp.to_i).abs
      return fail_with("QR code timestamp expired", bonid: bonid, status: :expired_or_not_found) if time_diff > 5.minutes
    rescue
      return fail_with("Invalid timestamp format", bonid: bonid, status: :invalid_format)
    end

    submission = IdentitySubmission.find_by(bonid: bonid, status: :approved)
    return fail_with("BonID not found", bonid: bonid, status: :not_found) unless submission
    return fail_with("BonID has expired", bonid: bonid, status: :expired) if submission.expires_at&.past?

    user = submission.user
    ensure_user_address(user)
    log_scan(submission, partner_slug)

    Result.new(
      success?: true,
      submission: submission,
      user: user,
      visitor: nil,
      redirect_to: officer_redirect_path(submission),
      status: :success
    )
  end

  def verify_signature(bonid, timestamp, signature)
    secret_key = Rails.application.credentials.dig(:bonid, :signature_secret)
    return false unless secret_key.present?

    payload  = { bonid: bonid, timestamp: timestamp.to_s }.to_json
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret_key, payload)

    Rails.logger.info("[BonID Signature] payload=#{payload}, signature=#{signature}, expected=#{expected}")

    ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected.to_s)
  rescue => e
    Rails.logger.error("[BonID Signature] Verification error: #{e.message}")
    false
  end

  def officer_redirect_path(submission)
    @url_helpers.new_officers_incident_report_path(bonid_submission_id: submission.id)
  rescue NameError => e
    Rails.logger.error("[BonidLookupService#officer_redirect_path] Route helper not found: #{e.message}")
    nil
  end

  def extract_partner_slug
    @params[:partner].presence ||
      Partner.find_by(id: @officer&.partner_id)&.slug ||
      "unknown"
  rescue => e
    Rails.logger.warn("[BonID Partner] Extraction failed: #{e.message}")
    "unknown"
  end

  def ensure_user_address(user)
    return if user&.address.present?

    commune = Commune.find_or_create_by(name: "Port-au-Prince")
    communal_section = CommunalSection.find_or_create_by(name: "1re Section Turgeau", commune: commune)

    user.create_address(
      commune: commune,
      communal_section: communal_section,
      street_address: "51 Angle Avenue Jean Paul II",
      postal_code: "HT6113",
      country: "Haiti"
    )
  rescue => e
    Rails.logger.error("[BonID Address] Failed to create: #{e.message}")
  end

  def log_scan(submission, partner_slug)
    partner = Partner.find_by(slug: partner_slug)

    QrScanLogger.log!(
      submission: submission,
      request: @request,
      source: "officer_lookup",
      officer: @officer,
      partner: partner
    )
  rescue => e
    Rails.logger.error("[BonID Scan] Logging failed: #{e.message}")
  end

  def log_manual_lookup(submission, bonid)
    FailedBonidLookup.create!(
      bonid: bonid,
      officer_id: @officer&.id,
      reason: "Manual BonID entry fallback",
      ip_address: @request&.remote_ip,
      user_agent: @request&.user_agent
    )
  rescue => e
    Rails.logger.warn("[BonID Manual] Logging failed: #{e.message}")
  end

  def log_suffix_lookup(submission, suffix)
    QrScanLogger.log!(
      submission: submission,
      request: @request,
      source: "officer_suffix_lookup",
      officer: @officer,
      partner: @officer&.partner
    )
    Rails.logger.info("[BonID Suffix Lookup] Officer #{@officer&.id} found submission #{submission.id} via suffix #{suffix}")
  rescue => e
    Rails.logger.warn("[BonID Suffix Lookup] Logging failed: #{e.message}")
  end

  def log_visitor_lookup(visitor, bonid)
    # Log visitor scan event using existing table columns
    VisitorScanEvent.create!(
      visitor_submission: visitor,
      bon_touris_id: bonid,
      input_method: "manual",
      status: "verified",
      ok: true,
      occurred_at: Time.current,
      ip_address: @request&.remote_ip,
      user_agent: @request&.user_agent,
      actor_kind: "officer",
      actor_label: "Officer ##{@officer&.id}",
      actor_verified: true
    )
    Rails.logger.info("[BonTouris Lookup] Officer #{@officer&.id} verified visitor #{visitor.id} via bonid #{bonid}")
  rescue => e
    Rails.logger.warn("[BonTouris Lookup] Logging failed: #{e.message}")
  end

  def log_six_digit_lookup(submission, digits, type)
    QrScanLogger.log!(
      submission: submission,
      request: @request,
      source: "officer_six_digit_lookup",
      officer: @officer,
      partner: @officer&.partner
    )
    Rails.logger.info("[BonID 6-Digit Lookup] Officer #{@officer&.id} found #{type} submission #{submission.id} via digits #{digits}")
  rescue => e
    Rails.logger.warn("[BonID 6-Digit Lookup] Logging failed: #{e.message}")
  end

  def log_six_digit_lookup_visitor(visitor, digits)
    VisitorScanEvent.create!(
      visitor_submission: visitor,
      bon_touris_id: digits,
      input_method: "manual_6digit",
      status: "verified",
      ok: true,
      occurred_at: Time.current,
      ip_address: @request&.remote_ip,
      user_agent: @request&.user_agent,
      actor_kind: "officer",
      actor_label: "Officer ##{@officer&.id}",
      actor_verified: true
    )
    Rails.logger.info("[BonTouris 6-Digit Lookup] Officer #{@officer&.id} verified visitor #{visitor.id} via digits #{digits}")
  rescue => e
    Rails.logger.warn("[BonTouris 6-Digit Lookup] Logging failed: #{e.message}")
  end

  def fail_with(message, bonid: nil, status: :failed)
    log_failure({ bonid: bonid }, message)
    Result.new(success?: false, submission: nil, user: nil, visitor: nil, redirect_to: nil, error: message, status: status)
  end

  def log_failure(payload, reason)
    FailedBonidLookup.create!(
      bonid: payload[:bonid],
      verification_token: payload[:timestamp] || payload[:verification_token],
      signature: payload[:signature],
      officer_id: @officer&.id,
      reason: reason,
      ip_address: @request&.remote_ip,
      user_agent: @request&.user_agent
    )
  rescue => e
    Rails.logger.warn("[BonID Failure] Logging failed: #{e.message}")
  end
end
