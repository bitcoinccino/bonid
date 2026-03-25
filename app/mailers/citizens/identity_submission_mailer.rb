# app/mailers/citizens/identity_submission_mailer.rb
module Citizens
  class IdentitySubmissionMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"
    layout "mailer"


     # --- New addition ---
     def submission_received_email(submission)
      @submission = submission
      @citizen = submission.user
      @email_product = "bonid"
      mail(
        to: @citizen.email,
        subject: "BonID: Nou resevwa soumisyon verifikasyon ou"
      )
    end

    def approved_email(submission)
      @submission = submission
      @email_product = "bonid"
      mail(to: submission.user.email, subject: "BonID: Verifikasyon ou apwouve!")
    end

    def rejected_email(submission)
      @submission = submission
      @email_product = "bonid"
      mail(to: submission.user.email, subject: "BonID: Soumisyon ou pa apwouve")
    end

    def reset_requested_email(submission)
      @submission = submission
      @email_product = "bonid"
      mail(to: submission.user.email, subject: "BonID: Demann reyinisyalizasyon resevwa")
    end

    def reset_approved_email(submission)
      @submission = submission
      @email_product = "bonid"
      mail(to: submission.user.email, subject: "BonID: Reyinisyalizasyon apwouve")
    end

    def reset_rejected_email(submission)
      @submission = submission
      @email_product = "bonid"
      mail(to: submission.user.email, subject: "BonID: Reyinisyalizasyon pa apwouve")
    end
  end
end
