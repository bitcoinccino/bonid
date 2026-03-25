# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  def bonid_approved
    user = User.first || User.new(email: "citizen@example.com", first_name: "Jean", last_name: "Louis")
    submission = IdentitySubmission.first || IdentitySubmission.new(id: 1, bonid: "MO-1968-M-OUEST-P-6790")
    UserMailer.bonid_approved(user, submission)
  end

  def bonid_rejected
    user = User.first || User.new(email: "citizen@example.com", first_name: "Marie", last_name: "Pierre")
    submission = IdentitySubmission.first || IdentitySubmission.new(id: 2, bonid: "PA-1975-F-ARTIBONITE-P-4312")
    UserMailer.bonid_rejected(user, submission)
  end

  def reset_approved
    user = User.first || User.new(email: "citizen@example.com", first_name: "Jacques", last_name: "Joseph")
    submission = IdentitySubmission.first || IdentitySubmission.new(id: 3, bonid: "JO-1984-M-NIPPES-P-8211")
    UserMailer.reset_approved(user, submission)
  end

  def reset_rejected
    user = User.first || User.new(email: "citizen@example.com", first_name: "Catherine", last_name: "Jean")
    submission = IdentitySubmission.first || IdentitySubmission.new(id: 4, bonid: "CA-1992-F-SUD-P-9834")
    UserMailer.reset_rejected(user, submission)
  end

  def teller_role_added
    user = User.first || User.new(email: "teller@example.com", first_name: "David", last_name: "Louis")
    partner = Partner.first || Partner.new(name: "Unibank", email: "contact@unibank.ht")
    UserMailer.teller_role_added(user:, partner:)
  end
end
