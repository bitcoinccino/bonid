module ApplicationHelper

  # app/helpers/application_helper.rb
  def submission_status_badge_class(status)
    case status
    when "pending" then "bg-warning text-dark"
    when "approved" then "bg-success text-white"
    when "rejected" then "bg-danger text-white"
    when "reset_requested" then "bg-info text-dark"
    else "bg-secondary text-white"
    end
  end

  def badge_class(status)
    case status.to_s
    when "approved" then "bg-success"
    when "pending" then "bg-warning text-dark"
    when "rejected" then "bg-danger"
    when "invalidated" then "bg-secondary text-white"
    else "bg-light text-dark"
    end
  end


  def format_datetime(datetime)
    return "-" if datetime.blank?
    datetime.strftime("%B %d, %Y %I:%M %p")
  end

  def rejection_reasons_options
    [
      "Missing CIN or Passport document",
      "CIN or Passport photo is blurry or unreadable",
      "CIN or Passport does not match selfie",
      "Selfie is missing",
      "Selfie is too blurry or unclear",
      "Proof of Address is missing",
      "Proof of Address is invalid (not a Digicel bill)",
      "Proof of Address is outdated",
      "Information provided is inconsistent",
      "Name mismatch between documents",
      "Expired identification document",
      "Low quality or incomplete document uploads",
      "Multiple submissions with conflicting information",
      "Identity could not be verified",
      "Suspicious or altered documents detected",
      "Document tampering suspected",
      "Duplicate identity submission detected",
      "Non-Haitian ID submitted",
      "Incomplete submission",
      "Other (please specify below)"
    ]
  end


  def submission_status_info(submission)
    if submission.status == "invalid"
      { text: "Invalid", badge_class: "bg-secondary text-white" }
    elsif submission.reset_request_status == "approved"
      { text: "BONID Reissued", badge_class: "bg-success" }
    elsif submission.reset_request_status == "rejected"
      { text: "Reset Rejected", badge_class: "bg-danger" }
    elsif submission.reset_request_status == "pending"
      { text: "Reset Pending", badge_class: "bg-warning" } # ✅ yellow badge
    elsif submission.reset_requested_at.present? && submission.reset_request_status.blank?
      { text: "Reset Requested", badge_class: "bg-warning" }
    else
      {
        text: submission.status.to_s.titleize,
        badge_class: badge_class(submission.status) # reuse helper
      }
    end
  end

  def submission_type_badge(submission)
    if submission.reset_requested_at.present? || submission.reset_request_status.present?
      ["Reissue Request", "bg-warning text-dark", "This is a request to reissue your BonID."]
    elsif submission.reissued_at.present?
      ["Resubmission", "bg-primary", "You've edited and resubmitted your verification."]
    elsif submission.created_at == submission.user.identity_submissions.minimum(:created_at)
      ["Initial Submission", "bg-info text-dark", "This was your very first verification submission."]
    else
      ["New Submission", "bg-secondary", "This is a new identity verification submission."]
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


  def user_friendly_rejection_reason(reason)
    return "" if reason.blank?
  
    case reason.strip
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
      reason
    end
  end
 
  # This method provides a list of guidelines for Admin using BonID.
  def guidelines
    [
      "Encrypt user data during storage and transmission to prevent unauthorized access.",
      "Access user data only for authorized purposes, such as verification or support.",
      "Do not share user data with third parties without explicit consent.",
      "Use BonID’s scan logs to audit identity checks and ensure accountability.",
      "Comply with Haiti’s data protection regulations and international privacy standards.",
      "Report any data breaches or suspicious activity immediately to BonID’s security team.",
      "Limit data retention to the minimum required period as per BonID protocol.",
      "Train staff on secure data handling practices to maintain user trust."
    ]
  end


  def pnh_ranks(format: :array)
    ranks = [
      { id: 1, name: 'Directeur Général', en_name: 'Director General', level: 8 },
      { id: 2, name: 'Inspecteur Général', en_name: 'Inspector General', level: 7 },
      { id: 3, name: 'Commissaire Divisionnaire', en_name: 'Divisional Commissioner', level: 6 },
      { id: 4, name: 'Commissaire de Police', en_name: 'Police Commissioner', level: 5 },
      { id: 5, name: 'Sous-Commissaire', en_name: 'Deputy Commissioner', level: 4 },
      { id: 6, name: 'Inspecteur de Police', en_name: 'Police Inspector', level: 3 },
      { id: 7, name: 'Agent Principal', en_name: 'Senior Agent', level: 2 },
      { id: 8, name: 'Agent de Police', en_name: 'Police Agent', level: 1 }
    ]
    case format
    when :array then ranks
    when :names then ranks.map { |r| r[:name] }
    when :select_options then ranks.map { |r| [r[:name], r[:id]] }
    when :hash then ranks.index_by { |r| r[:id] }
    else raise ArgumentError, "Invalid format: #{format}"
    end
  end
  


end
