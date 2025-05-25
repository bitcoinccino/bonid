module IdentitySubmissionsHelper
  require 'rqrcode'

  def has_verified_bonid?(user)
    user.identity_submissions.approved
        .where("expires_at > ?", Time.current)
        .exists?
  end

  def status_alert_type(submission)
    if submission.reset_request_status.present?
      case submission.reset_request_status
      when "pending" then "info"
      when "approved" then "success"
      when "rejected" then "danger"
      else "secondary"
      end
    else
      case submission.status
      when "pending" then "warning"
      when "approved" then "success"
      when "rejected" then "danger"
      when "revoked" then "secondary"
      else "info"
      end
    end
  end

  def status_icon(submission)
    if submission.reset_request_status.present?
      {
        "pending" => "ri-time-fill text-info",
        "approved" => "ri-checkbox-circle-fill text-success",
        "rejected" => "ri-close-circle-fill text-danger"
      }[submission.reset_request_status] || "ri-information-fill text-info"
    else
      {
        "pending" => "ri-time-fill text-warning",
        "approved" => "ri-checkbox-circle-fill text-success",
        "rejected" => "ri-close-circle-fill text-danger",
        "revoked" => "ri-shield-cross-fill text-secondary"
      }[submission.status] || "ri-information-fill text-info"
    end
  end

  def status_message(submission)
    if submission.reset_request_status.present?
      case submission.reset_request_status
      when "pending" then "Your BonID Reissue request is pending."
      when "approved" then "Your BonID has been successfully reissued."
      when "rejected" then "Your BonID reset request was rejected."
      else "Your BonID reset request is under review."
      end
    else
      case submission.status
      when "pending"
        case submission.submission_type
        when "resubmission"
          "You’ve corrected and resubmitted your BonID for review."
        when "reissue"
          "You’ve requested a new BonID. Your previous one has been revoked and your new request is being reviewed."
        else
          "Your BonID verification is pending."
        end
      when "approved" then "Your BonID verification was approved."
      when "rejected" then "Your BonID submission was rejected."
      when "revoked"
        # This should only happen if no reissue/resubmission exists
        "Your BonID has been revoked."
      else "Your BonID status is unknown."
      end
    end
  end

  def submission_status_info(submission)
    case
    when submission.reset_request_status == "pending"
      { text: "Reissue Pending", badge_class: "bg-info text-dark" }
    when submission.reset_request_status == "approved"
      { text: "Reissued", badge_class: "bg-success" }
    when submission.reset_request_status == "rejected"
      { text: "Reissue Rejected", badge_class: "bg-danger" }
    when submission.status == "approved"
      { text: "Verified", badge_class: "bg-success" }
    when submission.status == "pending"
      { text: "Pending Review", badge_class: "bg-warning text-dark" }
    when submission.status == "rejected"
      { text: "Rejected", badge_class: "bg-danger" }
    when submission.status == "revoked"
      { text: "Revoked", badge_class: "bg-secondary" }
    else
      { text: "Unknown", badge_class: "bg-dark" }
    end
  end

  def submission_type_badge(submission)
    case submission.submission_type
    when "initial"
      ["Initial Submission", "bg-primary", "Your first BonID verification."]
    when "resubmission"
      ["Resubmission", "bg-info text-dark", "You’ve corrected and resubmitted documents."]
    when "reissue"
      ["Reissue Request", "bg-dark", "You requested a new BonID after revocation or loss."]
    else
      ["Unknown Type", "bg-secondary", "Submission type is undefined."]
    end
  end

  def submission_type_description(submission)
    case submission.submission_type
    when "initial"
      "This is your first BonID verification request."
    when "resubmission"
      "You’ve corrected and resubmitted your BonID for review."
    when "reissue"
      "This is a new BonID request submitted after your previous one was revoked or lost."
    else
      "This submission is being processed."
    end
  end

  def user_friendly_rejection_reason(reason)
    reason&.humanize || "No specific reason provided."
  end

  # Determines if the user is allowed to request a new BonID (reissue flow)
  def eligible_for_new_bonid_request?(user, submissions)
    return false unless user && profile_complete?(user)

    last = submissions&.first
    return false if last.nil?

    # Block new request if a reset or reissue is already pending
    return false if last.reset_request_status == "pending"
    return false if last.submission_type == "reissue" && last.status == "pending"

    # Allow new BonID if any of the following apply
    last.rejected? ||
      last.status == "revoked" ||
      (last.expires_at.present? && last.expires_at < Time.current) ||
      (last.created_at < 6.months.ago)
  end


  def formatted_rejection(submission)
    return unless submission.rejection_reason.present?

    reason_text = rejection_reason_description(submission.rejection_reason)
    detail_text = submission.other_reason.to_s.strip

    detail_text.present? ? "#{reason_text}: #{detail_text}" : reason_text
  end

  def additional_proof_documents
    [
      ["Digicel Phone Bill", :digicel_phone_bill],
      ["Natcom Phone Bill", :natcom_phone_bill],
      ["Authenticated Baptismal Certificate", :baptismal_certificate],
      ["Birth Certificate", :birth_certificate],
      ["Adoption Certificate", :adoption_certificate],
      ["Monitor Copy for Naturalized Haitians", :naturalization_monitor_copy],
      ["Extract from Archives", :archives_extract],
      ["PNH Record", :pnh_record],
      ["Bank Record", :bank_record],
      ["Western Union Record", :western_union_record],
      ["Moneygram Record", :moneygram_record],
      ["Sendwave Record", :sendwave_record],
      ["Unitransfer Record", :unitransfer_record],
      ["Taptap Record", :taptap_record],
      ["Immatriculation de voiture", :car_registration]
    ]
  end

  def reissue_reasons_options
    [
      "Lost access to previous QR code",
      "Information changed (e.g., name, address, or contact details)",
      "Document updates (e.g., new passport or ID)",
      "QR code expired",
      "Suspected compromise or unauthorized access",
      "Technical issues (e.g., QR code not scanning)",
      "Legal or administrative requirement",
      "Other"
    ]
  end

  def submission_status_badge(status)
    case status
    when "approved" then "bg-success"
    when "pending" then "bg-warning text-dark"
    when "rejected" then "bg-danger"
    else "bg-secondary"
    end
  end

  def bulk_action_message(action, count)
    case action
    when "approve_bin"
      "#{pluralize(count, 'submission')} from BonBin successfully approved and activated ✅"
    when "reject_bin"
      "#{pluralize(count, 'submission')} from BadBin successfully rejected ❌"
    else
      "Bulk action completed."
    end
  end

  def partner_trust_badge(partner)
    return unless partner

    sector = partner.sector.to_s.downcase

    case sector
    when /government|embassy|ministry/
      {
        class: "badge bg-light border border-primary text-primary px-3 py-2 rounded-pill d-inline-flex align-items-center",
        icon: "ri-government-line",
        label: "Affiliated with"
      }
    when /education|university|school/
      {
        class: "badge bg-warning-subtle text-warning border border-warning-subtle px-3 py-2 rounded-pill d-inline-flex align-items-center",
        icon: "ri-award-line",
        label: "Certified by"
      }
    when /bank|fintech|insurance/
      {
        class: "badge bg-secondary-subtle text-dark border border-secondary-subtle px-3 py-2 rounded-pill d-inline-flex align-items-center",
        icon: "ri-briefcase-line",
        label: "Trusted by"
      }
    else
      {
        class: "badge bg-success-subtle text-success border border-success-subtle px-3 py-2 rounded-pill d-inline-flex align-items-center",
        icon: "ri-thumb-up-line",
        label: "Verified by"
      }
    end
  end
end  



