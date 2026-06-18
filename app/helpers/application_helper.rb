module ApplicationHelper
  # Whether the paused BonTouris feature is enabled. Used to hide nav links
  # to gated staff pages. Mirrors the controller guard (BontourisPausable).
  def bontouris_enabled?
    BontourisPausable.enabled?
  end

  # === Role Helpers ===
  def current_role
    if admin_signed_in?
      :admin
    elsif partner_admin_signed_in?
      :partner_admin
    elsif officer_signed_in?
      :officer
    elsif citizen_signed_in?
      :citizen
    else
      :guest
    end
  end

  def current_citizen?
    current_citizen.present? rescue false
  end

  def current_officer?
    current_officer.present? rescue false
  end

  # === Citizen Profile ===
  def profile_complete?(citizen)
    return false if citizen.blank?
    citizen.respond_to?(:profile_complete?) && citizen.profile_complete?
  end

  # === Status + Badge Helpers ===
  def submission_status_badge_class(status)
    case status.to_s
    when "pending" then "bg-warning text-dark"
    when "approved" then "bg-success text-white"
    when "rejected" then "bg-danger text-white"
    when "reset_requested" then "bg-info text-dark"
    when "revoked" then "bg-danger text-white"
    else "bg-secondary text-white"
    end
  end

  # Alias for views that use the shorter name
  alias_method :submission_status_badge, :submission_status_badge_class

  def haitian_badge_class(status)
    # Haitian-themed status color mapping
    case status.to_s
    when "approved"   then "bg-success text-white"          # Palm Green
    when "pending"    then "bg-warning text-dark"           # Gold
    when "rejected"   then "bg-danger text-white"           # Danger Red
    when "reviewing"  then "bg-primary text-white"          # Haitian Blue
    when "invalid"    then "bg-secondary text-white"
    else "bg-light text-dark"
    end
  end

  def badge_class(status)
    haitian_badge_class(status)
  end

  # === Face Match Badge Helpers ===
  def face_match_badge_class(status)
    case status.to_s
    when "match"            then "bg-success text-white"
    when "no_match"         then "bg-danger text-white"
    when "no_face_detected" then "bg-warning text-dark"
    when "error"            then "bg-secondary text-white"
    else "bg-light text-dark"
    end
  end

  def face_match_icon(status)
    case status.to_s
    when "match"            then "ri-checkbox-circle-line"
    when "no_match"         then "ri-close-circle-line"
    when "no_face_detected" then "ri-question-line"
    when "error"            then "ri-error-warning-line"
    else "ri-scan-2-line"
    end
  end

  # === Date Formatting ===
  def format_datetime(datetime)
    return "-" if datetime.blank?
    datetime.strftime("%B %d, %Y %I:%M %p")
  end

  # === Submission Status ===
  def submission_status_info(submission)
    if submission.status == "invalid"
      { text: "Invalid", badge_class: "bg-secondary text-white" }
    elsif submission.reset_request_status == "approved"
      { text: "BONID Reissued", badge_class: "bg-success" }
    elsif submission.reset_request_status == "rejected"
      { text: "Reset Rejected", badge_class: "bg-danger" }
    elsif submission.reset_request_status == "pending"
      { text: "Reset Pending", badge_class: "bg-warning" }
    elsif submission.reset_requested_at.present? && submission.reset_request_status.blank?
      { text: "Reset Requested", badge_class: "bg-warning" }
    else
      {
        text: submission.status.to_s.titleize,
        badge_class: badge_class(submission.status)
      }
    end
  end

  def submission_type_badge(submission)
    if submission.reset_requested_at.present? || submission.reset_request_status.present?
      [ "Reissue Request", "bg-warning text-dark", "This is a request to reissue your BonID." ]
    elsif submission.reissued_at.present?
      [ "Resubmission", "bg-primary", "You've edited and resubmitted your verification." ]
    elsif submission.created_at == submission.user.identity_submissions.minimum(:created_at)
      [ "Initial Submission", "bg-info text-dark", "This was your very first verification submission." ]
    else
      [ "New Submission", "bg-secondary", "This is a new identity verification submission." ]
    end
  end

  def submission_type_description(submission)
    if submission.reset_request_status.present?
      "You submitted a BonID reissue request."
    elsif submission.reissued_at.present?
      "This is a resubmission following a previous rejection."
    elsif submission.created_at == submission.user.identity_submissions.minimum(:created_at)
      "This is your first BonID verification submission."
    else
      "You’ve submitted a new BonID verification."
    end
  end

  # === Rejection Reason Mapping ===
  def user_friendly_rejection_reason(reason)
    return "" if reason.blank?

    case reason.strip
    when "inconsistent_info"
      "Some of the information you submitted does not match."
    when "Missing CIN or Passport document"
      "You need to upload either a CIN (both front and back) or a passport."
    when "CIN or Passport photo is blurry or unreadable"
      "Your ID photo is too blurry to be read clearly."
    when "CIN or Passport does not match selfie"
      "The ID document does not match your selfie."
    when "Selfie is missing"
      "A selfie is required for verification."
    when "Selfie is too blurry or unclear"
      "Your selfie is too blurry to verify your identity."
    when "Proof of Address is missing"
      "Please upload a proof of address (e.g., a Digicel bill)."
    when "Proof of Address is invalid (not a Digicel bill)"
      "Only Digicel bills are accepted as valid proof of address."
    when "Proof of Address is outdated"
      "Your proof of address document is too old."
    when "Information provided is inconsistent"
      "Some of the information you submitted does not match."
    when "Name mismatch between documents"
      "Your name is not consistent across your documents."
    when "Expired identification document"
      "Your ID is expired and can’t be used for verification."
    when "Low quality or incomplete document uploads"
      "Some uploaded documents are either incomplete or low quality."
    when "Multiple submissions with conflicting information"
      "You submitted conflicting information across multiple requests."
    when "Identity could not be verified"
      "We couldn’t verify your identity with the submitted documents."
    when "Suspicious or altered documents detected"
      "Some documents appear to be altered or suspicious."
    when "Document tampering suspected"
      "Your documents show signs of tampering."
    when "Duplicate identity submission detected"
      "You’ve already submitted an identity with matching data."
    when "Non-Haitian ID submitted"
      "Only Haitian-issued identification is accepted."
    when "Incomplete submission"
      "Some required documents or information are missing."
    when "Other (please specify below)"
      "Your submission was rejected for another reason. Please review your documents."
    when "Bulk rejection by admin"
      "Your submission was rejected during a batch review and didn’t meet verification criteria."
    else
      reason.humanize
    end
  end

  # === Submission Status Icon ===
  def status_icon(submission)
    if submission.status == "invalid"
      "bi bi-exclamation-circle text-secondary"  # Fallback for invalid
    elsif submission.reset_request_status == "approved"
      "bi bi-check-circle-fill text-success"     # Approved reset
    elsif submission.reset_request_status == "rejected"
      "bi bi-x-circle-fill text-danger"          # Rejected reset
    elsif submission.reset_request_status == "pending"
      "bi bi-hourglass-split text-warning"       # Pending reset
    elsif submission.reset_requested_at.present? && submission.reset_request_status.blank?
      "bi bi-arrow-clockwise text-warning"       # Reset requested (generic refresh icon)
    else
      case submission.status.to_s
      when "approved"   then "bi bi-check-circle-fill text-success"   # Palm Green equivalent
      when "pending"    then "bi bi-hourglass-split text-warning"     # Gold equivalent
      when "rejected"   then "bi bi-x-circle-fill text-danger"        # Danger Red
      when "reviewing"  then "bi bi-search text-primary"              # Haitian Blue (inspection icon)
      else "bi bi-question-circle text-secondary"                     # Unknown/fallback
      end
    end
  end

  # === Submission Status Message ===
  def status_message(submission)
    status_info = submission_status_info(submission)
    case status_info[:text]
    when "Invalid"
      "Your submission is invalid. Please review and resubmit."
    when "BONID Reissued"
      "Your BONID has been successfully reissued."
    when "Reset Rejected"
      "Your reset request was rejected. Check the rejection reason below."
    when "Reset Pending"
      "Your reset request is currently pending review."
    when "Reset Requested"
      "Your reset request has been submitted and is awaiting processing."
    when "Approved"
      "Your submission has been approved."
    when "Pending"
      "Your submission is pending review."
    when "Rejected"
      "Your submission was rejected. Check the rejection reason below."
    when "Reviewing"
      "Your submission is under review."
    else
      "Your submission status is #{status_info[:text].downcase}."
    end
  end

  # === Eligibility for New BonID Request ===
  # A citizen can request a new BonID only for: name change or expiration.
  # Requires: profile complete, has an approved BonID, no pending submission.
  def eligible_for_new_bonid_request?(user, submissions)
    return false if user.blank? || submissions.blank? || !profile_complete?(user)

    has_approved = submissions.any? { |s| s.status == "approved" }
    has_pending  = submissions.any? { |s| s.status.in?(%w[pending reviewing]) }

    has_approved && !has_pending
  end

  # === Partner Application Rejection Reasons ===
  # Matches Partner::REJECTION_REASONS
  def partner_rejection_reason_label(value)
    return "—" if value.blank?
    Partner::REJECTION_REASONS.key(value) || value.to_s.humanize
  rescue NameError
    # Prevents crash if constant not loaded yet
    value.to_s.humanize
  end

  # === Admin Guidelines ===
  def guidelines
    [
      "Encrypt user data during storage and transmission to prevent unauthorized access.",
      "Access user data only for authorized purposes, such as verification or support.",
      "Do not share user data with third parties without explicit consent.",
      "Use BonID’s scan logs to audit identity checks and ensure accountability.",
      "Comply with Haiti’s data protection regulations and international privacy standards.",
      "Report any data breaches or suspicious activity immediately to BonID’s security team.",
      "Limit data retention to the minimum required period as per BonID protocol.",
      "Train staff on secure data handling practices to maintain user trust.",
      "Birth Certificate (Extrait de Naissance): Only accept the authentic, blue-colored version issued by the National Archives (Archives Nationales d’Ha\u00EFti). Reject local town hall (mairie) copies."
    ]
  end

  # === PII Masking Helpers ===
  # Masks an email address: "remedavid@yahoo.com" → "re*****id@yahoo.com"
  def mask_email(email)
    return "—" if email.blank?

    local, domain = email.split("@", 2)
    return email if local.blank? || domain.blank?

    if local.length <= 2
      masked_local = local[0] + "*"
    elsif local.length <= 4
      masked_local = local[0] + ("*" * (local.length - 1))
    else
      masked_local = local[0..1] + ("*" * (local.length - 4)) + local[-2..]
    end

    "#{masked_local}@#{domain}"
  end

  # Masks a BonID: "JM-1968-M-OUEST-P2334-697280" → "MB••••••••697280"
  def mask_bonid(bonid)
    return "—" if bonid.blank?

    stripped = bonid.gsub("-", "")
    last6 = stripped.last(6)
    dots = "•" * [ stripped.length - 8, 6 ].max
    "MB#{dots}#{last6}"
  end

  # Maps raw API endpoints to human-readable, citizen-focused action labels.
  # Used in the Digital Identity Hub (Law Enforcement API Management page).
  def humanize_api_endpoint(endpoint)
    return "Unknown Action" if endpoint.blank?

    {
      "/api/v1/verify_identity"   => "Verified Identity",
      "/api/v1/crime_status"      => "Checked Crime Status",
      "/api/v1/crime_certificate" => "Crime Certificate Request",
      "/api/v1/lookup"            => "BonID Lookup",
      "/api/v1/consent"           => "Consent Verification",
      "/api/v1/scan"              => "BonID Scan"
    }[endpoint] || endpoint.split("/").last.to_s.titleize
  end

  # === Address Formatting ===
  def format_address(address)
    return "N/A" if address.blank?

    [
      address.street_address,
      address.locality,
      address.postal_code,
      address.commune&.name,
      address.department&.name
    ].compact.join(", ")
  end

  # === QR Scan Log Device/Browser Extractor ===
  def extract_browser_name(user_agent)
    return "Unknown Device" if user_agent.blank?

    device =
      case user_agent
      when /iPhone/i then "iPhone"
      when /iPad/i   then "iPad"
      when /Android/i then "Android"
      when /Windows/i then "Windows"
      when /Macintosh|Mac OS X/i then "Mac"
      when /Linux/i then "Linux"
      else "Device"
      end

    browser =
      case user_agent
      when /Chrome/i then "Chrome"
      when /Safari/i then user_agent.include?("Chrome") ? "Chrome" : "Safari"
      when /Firefox/i then "Firefox"
      when /Edge/i then "Edge"
      when /Opera|OPR/i then "Opera"
      else "Browser"
      end

    "#{device} / #{browser}"
  rescue
    "Unknown"
  end

  # === Transaction Consent Status Border ===
  # Accepts effective_status (already resolved for time-expired pending consents)
  def txn_status_border_class(status)
    case status.to_s
    when "pending"  then "txn-border-warning"
    when "approved" then "txn-border-success"
    when "denied"   then "txn-border-danger"
    when "expired"  then "txn-border-muted"
    else ""
    end
  end

  # === Document Update Detection ===
  # Checks if a document was updated after the submission was created
  # Used to show "Updated" badge on re-uploaded documents
  def document_updated?(submission, field)
    return false unless submission.respond_to?(field)

    attachment = field == :photo ? submission.user&.photo : submission.send(field)
    return false unless attachment&.attached?

    # Check if the attachment was created after the submission
    blob_created_at = attachment.blob&.created_at
    return false unless blob_created_at

    # Document is considered "updated" if it was attached more than 1 minute after submission creation
    blob_created_at > (submission.created_at + 1.minute)
  rescue
    false
  end
end
