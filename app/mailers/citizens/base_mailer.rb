# frozen_string_literal: true

module Citizens
  class BaseMailer < VerifyemMailer
    before_action { @email_product = "bonid" } # citizen emails are BonID
    layout "mailer" # shared Haitian-blue email style (layouts/mailer)
  end
end
