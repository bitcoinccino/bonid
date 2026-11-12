class VerifyemMailer < ActionMailer::Base
  # Verifyem is the parent site: partner, admin, agent and waitlist emails
  # are Verifyem-level. Product mailers override (Citizens::BaseMailer →
  # "bonid"); an action can still set @email_product itself.
  before_action { @email_product ||= "verifyem" }
  default from: "noreply@verifyem.ht"
  layout "mailer" # shared Haitian-blue email style (layouts/mailer)
end
