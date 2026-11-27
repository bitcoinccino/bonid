# frozen_string_literal: true

module Citizens
  class BaseMailer < VerifyemMailer
    before_action { @email_product = "bonid" } # citizen emails are BonID
    layout "mailer" # shared Haitian-blue email style (layouts/mailer)

    private

    # Citizen emails go out in the citizen's own language (Paramèt → Lang,
    # first set from the language of the sign-up page), not the language of
    # whatever triggered them: an officer's review, a partner's API call, a
    # background job. Wrap the mail(...) call so the subject, body and
    # layout all render in it.
    def with_citizen_locale(user, &block)
      I18n.with_locale(user&.portal_locale || "ht", &block)
    end
  end
end
