# frozen_string_literal: true

require "rails_helper"

RSpec.describe WaitlistMailer, type: :mailer do
  let(:commune) { (Commune.first || create(:commune)).tap { |c| c.update!(code: "HT0112") } }
  let(:signup)  { WaitlistSignup.create!(email: "marie@example.com", signup_type: "citizen", commune: commune) }

  def html(mail) = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s

  it "invitation links to /signup?invite=<code> on the app's configured host and shows the code" do
    code = InviteCode.create!(code_type: "personal", commune: commune)
    body = html(described_class.invitation(signup, code))
    expect(body).to match(%r{href="https?://[^"/]+/signup\?invite=#{Regexp.escape(code.code)}"})
    expect(body).to include(code.code)
    expect(body).not_to include("bonid.ht")
    expect(body).not_to include("patnè verifye")
  end

  it "commune launch email links to /signup?commune=<admin code>" do
    body = html(described_class.commune_launched(signup))
    expect(body).to match(%r{href="https?://[^"/]+/signup\?commune=HT0112"})
    expect(body).not_to include("users/sign_up")
  end

  it "confirmation share link uses the app's host" do
    body = html(described_class.confirmation(signup))
    expect(body).to match(%r{https?://[^"/]+/enskri\?ref=#{signup.referral_code}})
  end
end
