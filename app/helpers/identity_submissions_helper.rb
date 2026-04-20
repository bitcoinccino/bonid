# app/helpers/identity_submissions_helper.rb

module IdentitySubmissionsHelper
  # Returns formatted status information for display
  def submission_status_display(submission)
    case submission.status.to_s
    when "pending"
      {
        badge_class: "bg-warning-subtle text-warning border border-warning",
        icon: "ri-time-line",
        text: "Under Review",
        short_description: "Being verified by our team",
        full_description: "Your submission is currently being reviewed by our verification team. This process usually takes 2-5 business days.",
        timeline: "Expected completion: #{(submission.created_at + 5.days).strftime('%B %d, %Y')}",
        action: nil
      }
    when "approved"
      {
        badge_class: "bg-success-subtle text-success border border-success",
        icon: "ri-checkbox-circle-line",
        text: "Verified ✓",
        short_description: "Your BonID is active",
        full_description: "Congratulations! Your identity has been verified and your BonID is now active.",
        timeline: "Approved on #{submission.verified_at&.strftime('%B %d, %Y')}",
        action: {
          text: "View Certificate",
          url: verified_profile_citizens_identity_submission_path(submission.public_token),
          class: "btn-success"
        }
      }
    when "rejected"
      {
        badge_class: "bg-danger-subtle text-danger border border-danger",
        icon: "ri-close-circle-line",
        text: "Rejected",
        short_description: "Resubmission required",
        full_description: "Your submission was not approved. Please review the reason below and resubmit with corrections.",
        timeline: "Rejected on #{submission.updated_at.strftime('%B %d, %Y')}",
        reason: submission.rejection_reason || "Documents unclear or incomplete",
        action: {
          text: "Resubmit Now",
          url: new_citizens_identity_submission_path(resubmission_from: submission.public_token),
          class: "btn-danger"
        }
      }
    when "expired"
      {
        badge_class: "bg-secondary-subtle text-secondary border border-secondary",
        icon: "ri-calendar-line",
        text: "Expired",
        short_description: "Renewal needed",
        full_description: "Your BonID has expired and is no longer valid. Please renew to continue using BonID services.",
        timeline: "Expired on #{submission.expires_at&.strftime('%B %d, %Y')}",
        action: {
          text: "Renew BonID",
          url: new_citizens_identity_submission_path,
          class: "btn-secondary"
        }
      }
    when "revoked"
      {
        badge_class: "bg-dark-subtle text-dark border border-dark",
        icon: "ri-forbid-line",
        text: "Revoked",
        short_description: "No longer active",
        full_description: "This BonID has been revoked and is no longer valid.",
        timeline: "Revoked on #{submission.updated_at.strftime('%B %d, %Y')}",
        action: nil
      }
    else
      {
        badge_class: "bg-light text-dark border border-secondary",
        icon: "ri-question-line",
        text: submission.status.humanize,
        short_description: "Status unknown",
        full_description: "Please contact support for more information.",
        timeline: nil,
        action: nil
      }
    end
  end

  # Renders status badge
  def status_badge(submission, size: :normal)
    info = submission_status_display(submission)
    badge_size = size == :large ? "px-4 py-2 fs-6" : "px-3 py-1"

    content_tag :span, class: "badge #{info[:badge_class]} #{badge_size} fw-semibold d-inline-flex align-items-center gap-2" do
      content_tag(:i, nil, class: info[:icon]) + " #{info[:text]}"
    end
  end

  # Renders full status card
  def status_card(submission)
    info = submission_status_display(submission)
    alert_class = "alert alert-#{alert_color_for_status(submission.status)} border rounded-4"

    content_tag :div, class: alert_class do
      content_tag(:div, class: "d-flex align-items-start") do
        icon_html = content_tag(:i, nil, class: "#{info[:icon]} fs-3 me-3 mt-1")

        details_html = content_tag(:div, class: "flex-grow-1") do
          title = content_tag(:h6, info[:text], class: "fw-bold mb-2")
          description = content_tag(:p, info[:full_description], class: "mb-2")

          timeline_html = if info[:timeline]
            content_tag(:p, class: "mb-2 small text-muted") do
              content_tag(:i, nil, class: "ri-calendar-line me-1") + " #{info[:timeline]}"
            end
          else
            ""
          end

          reason_html = if info[:reason]
            content_tag(:div, class: "alert alert-light border mt-2 mb-2") do
              content_tag(:strong, "Reason: ") + info[:reason]
            end
          else
            ""
          end

          action_html = if info[:action]
            content_tag(:div, class: "mt-3") do
              link_to info[:action][:url],
                      class: "btn #{info[:action][:class]} rounded-pill px-4 fw-semibold" do
                content_tag(:i, nil, class: "ri-arrow-right-line me-2") + info[:action][:text]
              end
            end
          else
            ""
          end

          title + description + timeline_html + reason_html + action_html
        end

        icon_html + details_html
      end
    end
  end

  private

  def alert_color_for_status(status)
    case status.to_s
    when "pending" then "warning"
    when "approved" then "success"
    when "rejected" then "danger"
    when "expired" then "secondary"
    when "revoked" then "dark"
    else "light"
    end
  end

  # Check if user profile is complete
  def profile_complete?(user)
    return true if user.identity_submissions.approved.exists?

    # Basic completeness check
    user.first_name.present? &&
    user.last_name.present? &&
    user.dob.present? &&
    user.email.present?
  end
end
