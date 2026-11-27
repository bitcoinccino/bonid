# frozen_string_literal: true

# Verification and reset decisions, in the citizen's language.
module Citizens
  class IdentitySubmissionMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"

    def submission_received_email(submission) = notify(submission, :received)
    def approved_email(submission)            = notify(submission, :approved)
    def rejected_email(submission)            = notify(submission, :rejected)
    def reset_requested_email(submission)     = notify(submission, :reset_requested)
    def reset_approved_email(submission)      = notify(submission, :reset_approved)
    def reset_rejected_email(submission)      = notify(submission, :reset_rejected)

    private

    def notify(submission, kind)
      @submission = submission
      @citizen = submission.user
      with_citizen_locale(@citizen) do
        mail(to: @citizen.email, subject: t("mailers.identity_submission.#{kind}.subject"))
      end
    end
  end
end
