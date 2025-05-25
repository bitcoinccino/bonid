# app/mailers/officer_mailer.rb
class OfficerMailer < ApplicationMailer
  def invitation(officer)
    @officer = officer
    @url = accept_invitation_url(token: officer.invitation_token)
    mail(to: @officer.email, subject: "You're invited to BonID as a PNH Officer")
  end
end
