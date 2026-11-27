# frozen_string_literal: true

require "rails_helper"

RSpec.describe WaitlistMailer, type: :mailer do
  let(:commune) { (Commune.first || create(:commune)).tap { |c| c.update!(code: "HT0112") } }
  let(:signup)  { WaitlistSignup.create!(email: "marie@example.com", signup_type: "citizen", commune: commune) }

  def html(mail) = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s

  it "invitation links to /signup?invite=<code> in the person's language and shows the code" do
    signup.update!(locale: "fr")
    code = InviteCode.create!(code_type: "personal", commune: commune)
    mail = described_class.invitation(signup, code)
    body = CGI.unescapeHTML(html(mail))
    expect(body).to match(%r{href="https?://[^"/]+/signup\?invite=#{Regexp.escape(code.code)}&lang=fr"})
    expect(body).to include(code.code, "Créer mon compte", "L’équipe BonID")
    expect(mail.subject).to eq("Vous êtes invité sur BonID ! Créez votre compte")
    expect(body).not_to include("bonid.ht", "Kreye kont mwen", "Create my account", "patnè verifye")
  end

  it "commune launch email links to /signup?commune=<admin code>, in one language" do
    signup.update!(locale: "en")
    mail = described_class.commune_launched(signup)
    body = CGI.unescapeHTML(html(mail))
    expect(body).to match(%r{href="https?://[^"/]+/signup\?commune=HT0112&lang=en"})
    expect(mail.subject).to eq("BonID is live in #{commune.name}!")
    expect(body).to include("Create my account", "The BonID Team")
    expect(body).not_to include("Kreye kont mwen", "Créer mon compte", "users/sign_up", "English:")
  end

  it "launch and invite emails default to Kreyòl" do
    code = InviteCode.create!(code_type: "personal")
    expect(described_class.commune_launched(signup).subject).to eq("BonID disponib nan #{commune.name}!")
    expect(described_class.invitation(signup, code).subject).to start_with("Ou envite sou BonID!")
  end

  describe "confirmation" do
    {
      "ht" => ["Ou sou lis la!", "Pataje sou WhatsApp", "Ekip BonID"],
      "fr" => ["Vous êtes inscrit !", "Partager sur WhatsApp", "L’équipe BonID"],
      "en" => ["You're on the list!", "Share on WhatsApp", "The BonID Team"]
    }.each do |lang, (subject, whatsapp, signoff)|
      it "is sent in #{lang} only, from noreply@verifyem.ht" do
        signup.update!(locale: lang, first_name: "Rose")
        mail = described_class.confirmation(signup)
        body = CGI.unescapeHTML(html(mail))
        expect(mail.from).to eq(["noreply@verifyem.ht"])
        expect(mail.subject).to eq(subject)
        expect(body).to include(whatsapp, signoff)
        others = { "ht" => "Pataje sou WhatsApp", "fr" => "Partager sur WhatsApp", "en" => "Share on WhatsApp" }.except(lang)
        others.each_value { |text| expect(body).not_to include(text) }
        expect(body).not_to include("English:", "Francais:", "— ")
      end
    end

    it "falls back to Kreyòl for signups without a language" do
      expect(described_class.confirmation(signup).subject).to eq("Ou sou lis la!")
    end

    it "uses the BonID footer, not the Verifyem one" do
      body = CGI.unescapeHTML(html(described_class.confirmation(signup)))
      expect(body).to include("Yon idantite dijital prive")
      expect(body).not_to include("Digital identity platform.")
    end
  end

  it "confirmation share link uses the app's host" do
    body = html(described_class.confirmation(signup))
    expect(body).to match(%r{https?://[^"/]+/enskri\?ref=#{signup.referral_code}})
  end
end
