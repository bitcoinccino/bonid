# frozen_string_literal: true

require "rails_helper"

RSpec.describe Citizens::CitizenMailer, "#otp_login", type: :mailer do
  let(:user) { create(:user, first_name: "Davidson ", preferred_locale: "ht") }

  def deliver(locale: nil)
    described_class.with(user: user, otp: "798450", locale: locale).otp_login
  end

  def bodies(mail)
    [mail.html_part.body.decoded, mail.text_part.body.decoded]
  end

  it "sends in the language the citizen was using on the login page" do
    mail = deliver(locale: "fr")
    expect(mail.subject).to eq("BonID : votre code de connexion")
    bodies(mail).each do |b|
      expect(b).to include("798450", "Bonjour Davidson,", "10 minutes", "L’équipe BonID")
      expect(b).not_to include("Dear", "Security Team")
    end
  end

  it "falls back to the saved portal language (Kreyòl)" do
    mail = deliver
    expect(mail.subject).to eq("BonID: Kòd koneksyon ou")
    bodies(mail).each { |b| expect(b).to include("Bonjou Davidson,", "10 minit", "Ekip BonID") }
  end

  it "sends in English when asked" do
    bodies(deliver(locale: "en")).each { |b| expect(b).to include("Hello Davidson,", "The BonID Team") }
  end

  it "points to the Verifyem support address with no 5-minute claim" do
    %w[ht fr en].each do |l|
      bodies(deliver(locale: l)).each do |b|
        expect(b).to include("support@verifyem.ht")
        expect(b).not_to include("bonid.ht", "5 min")
      end
    end
  end
end
