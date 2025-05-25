class IdentitySubmissionMailer < ApplicationMailer
  def reset_rejected_email(submission)
    @submission = submission
    mail(to: @submission.user.email, subject: "❌ Your BonID Reset Was Rejected")
  end

  def approved_email(submission)
    @submission = submission
    mail(to: @submission.user.email, subject: "🎉 Your BonID Submission Has Been Approved!")
  end

  def rejected_email(submission)
    @submission = submission
    mail(to: @submission.user.email, subject: "🚫 Your BonID Submission Was Rejected")
  end

  def reset_requested_email(submission)
    @submission = submission
    mail(to: @submission.user.email, subject: "🔁 Your Reset Request Was Received")
  end

  def reset_approved_email(submission)
    @submission = submission
    mail(to: @submission.user.email, subject: "✅ Your BonID Reset Has Been Approved")
  end

  def rejection_email(submission)
    @submission = submission
    mail(to: @submission.user.email, subject: "Your BonID Submission Was Rejected")
  end
  
end

