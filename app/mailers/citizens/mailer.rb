# frozen_string_literal: true

module Citizens
  class BaseMailer < VerifyemMailer
    default from: "bonid@verifyem.ht"
    layout "mailer"
  end
end
