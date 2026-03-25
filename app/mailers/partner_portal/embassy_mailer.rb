# app/mailers/partner_portal/embassy_mailer.rb
module PartnerPortal
  class EmbassyMailer < VerifyemMailer
    # === Embassy Notification ===
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
        to: @user.email,
        subject: subject
      )
    end
  end
end
