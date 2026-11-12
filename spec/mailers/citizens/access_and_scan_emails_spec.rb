# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Citizen access & scan emails", type: :mailer do
  # Emails go out in the citizen's portal language; most examples here pin
  # the English copy.
  let(:citizen) { create(:user, :with_address, :identity_verified, first_name: "Davidson", last_name: "Louis", preferred_locale: "en") }
  let(:partner) { create(:partner, :approved, name: "Zèllus", sector: "fintech") }

  def grant(status: :approved, scopes: %w[openid profile phone identity:verify])
    ConsentGrant.create!(citizen: citizen, partner: partner, status: status,
                         requested_scopes: scopes, granted_scopes: scopes,
                         granted_at: Time.current, expires_at: Time.zone.local(2027, 2, 6))
  end

  def body_of(mail) = mail.html_part ? mail.html_part.body.decoded : mail.body.decoded

  describe "shared layout" do
    it "has no monogram, product name block or 'by VERIFYEM', and the new footer line" do
      mail = Citizens::AccessMailer.with(grant: grant).access_granted
      body = body_of(mail)
      expect(body).not_to include("by VERIFYEM")
      expect(body).to include("#00209F")
      expect(body).to include("A private digital identity, not a government ID.")
      expect(body).not_to include("Idantite Dijital Repiblik Dayiti")
    end
  end

  describe "footer by product" do
    it "uses the Verifyem line and English copyright on partner/admin emails" do
      html = ApplicationController.render(template: "layouts/mailer", layout: false,
                                          assigns: { email_product: "verifyem" })
      expect(html).to include("Digital identity platform.")
      expect(html).not_to include("not a government ID")
      expect(html).to include("Verifyem &middot; All rights reserved")
    end

    it "falls back to BonID for an unknown product instead of crashing" do
      html = ApplicationController.render(template: "layouts/mailer", layout: false,
                                          assigns: { email_product: "nope" })
      expect(html).to include("Verify once, use anywhere.")
    end
  end

  describe "access granted" do
    it "explains in plain English what the partner can see" do
      mail = Citizens::AccessMailer.with(grant: grant).access_granted
      body = body_of(mail)
      expect(mail.to).to eq([ citizen.email ])
      expect(mail.subject).to eq("BonID: Zèllus can now see your information")
      expect(body).to include("Name, date of birth and photo", "Phone number", "Photo and face check")
      expect(body).to include("Feb 6, 2027")
      expect(body).not_to include("identity:verify")
      expect(body).not_to include("openid")
    end
  end

  describe "language" do
    it "sends the access email in the citizen's portal language" do
      citizen.update!(preferred_locale: "ht")
      mail = Citizens::AccessMailer.with(grant: grant).access_granted
      expect(mail.subject).to eq("BonID: Zèllus ka wè enfòmasyon ou kounye a")
      body = body_of(mail)
      expect(body).to include("Non, dat nesans ak foto")
      expect(body).to include("Yon idantite dijital prive, se pa yon ID gouvènman.")
    end

    it "sends it in French when the citizen picked French" do
      citizen.update!(preferred_locale: "fr")
      mail = Citizens::AccessMailer.with(grant: grant).access_granted
      expect(mail.subject).to eq("BonID : Zèllus peut désormais voir vos informations")
    end
  end

  describe "access removed" do
    it "confirms removal and the 30-day deletion rule" do
      g = grant
      g.update_columns(status: ConsentGrant.statuses[:revoked], revoked_at: Time.current)
      mail = Citizens::AccessMailer.with(grant: g).access_removed
      expect(mail.subject).to eq("BonID: Zèllus can no longer see your information")
      expect(body_of(mail)).to include("within 30 days")
    end
  end

  describe "when they're sent" do
    it "sends 'access granted' when a partner is given access" do
      expect { grant }.to have_enqueued_mail(Citizens::AccessMailer, :access_granted)
    end

    it "sends 'access removed' when an approved access is removed" do
      g = grant
      expect { g.revoke!(reason: "Citizen revoked from dashboard") }
        .to have_enqueued_mail(Citizens::AccessMailer, :access_removed)
    end

    it "sends nothing when a pending request is declined (that's not a removal)" do
      g = grant(status: :pending)
      expect { g.revoke!(reason: "Citizen denied consent") }
        .not_to have_enqueued_mail(Citizens::AccessMailer, :access_removed)
    end
  end
end

RSpec.describe "Wallet QR scan email", type: :request do
  let(:citizen) { create(:user, :with_address, first_name: "Davidson", last_name: "Louis") }
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  it "emails the citizen when someone scans their wallet QR with a phone" do
    expect {
      get "/citizens/identity_submissions/verify", params: { verification_token: submission.verification_token }
    }.to have_enqueued_mail(Citizens::QrScanMailer, :scan_alert)
  end

  it "writes the scan alert in plain English on the shared layout" do
    get "/citizens/identity_submissions/verify", params: { verification_token: submission.verification_token }
    log = submission.qr_scan_logs.order(:created_at).last
    mail = Citizens::QrScanMailer.scan_alert(log)
    body = mail.html_part ? mail.html_part.body.decoded : mail.body.decoded
    expect(mail.subject).to start_with("BonID: Your BonID was checked")
    expect(body).to include("Someone using a phone camera")
    expect(body).not_to include("IP Address")
    expect(body).not_to include("by VERIFYEM")
  end
end
