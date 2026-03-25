# frozen_string_literal: true

module Partners
  class EmbassyMailer < VerifyemMailer
    # Sends embassy-specific emails from country-based addresses.
    #
    # @param user [User] recipient user
    # @param embassy [String, Symbol] embassy country code (e.g. :fr, :us)
    # @param subject [String] email subject line
    # @param body [String] message body
    def embassy_email(user, embassy, subject:, body:)
      @user = user
      @body = body

      from_address = case embassy.to_sym
      when :fr then "embassy.fr@bonid.ht"
      when :us then "embassy.us@bonid.ht"
      when :ca then "embassy.ca@bonid.ht"
      when :mx then "embassy.mx@bonid.ht"
      else "embassy@bonid.ht"
      end

      mail(
        from: from_address,
        to:   @user.email,
        subject: subject
      )
    end
  end
end
