# frozen_string_literal: true

require "rails_helper"

# Citizen emails go out in the citizen's own language (users.preferred_locale,
# set from the sign-up page and changed under Paramèt → Lang), whatever the
# language of the request or job that sends them.
RSpec.describe "Citizen emails in the citizen's language", type: :mailer do
  let(:citizen) { create(:user, :with_address, first_name: "Davidson", last_name: "Louis", preferred_locale: "en") }
  let(:submission) { create(:identity_submission, user: citizen) }

  def body_of(mail) = (mail.html_part || mail).body.decoded

  # Copy that must not leak into another language's email
  KREYOL_MARKERS = [ "Bonjou", "Ekip BonID", "apwouve" ].freeze
  ENGLISH_MARKERS = [ "Hi ", "The BonID Team", "Dear " ].freeze

  {
    submission_received_email: "BonID: We received your verification request",
    approved_email: "BonID: Your verification is approved!",
    rejected_email: "BonID: Your submission was not approved",
    reset_requested_email: "BonID: Reset request received",
    reset_approved_email: "BonID: Reset approved",
    reset_rejected_email: "BonID: Reset not approved"
  }.each do |email, english_subject|
    describe "IdentitySubmissionMailer##{email}" do
      it "is all English for an English-speaking citizen" do
        mail = Citizens::IdentitySubmissionMailer.public_send(email, submission)
        expect(mail.to).to eq([ citizen.email ])
        expect(mail.subject).to eq(english_subject)
        body = body_of(mail)
        expect(body).to include("Hi <strong>Davidson</strong>,", "The BonID Team")
        expect(body).not_to include(*KREYOL_MARKERS)
        expect(body).not_to include("translation missing")
      end

      it "is all Kreyòl for a Kreyòl-speaking citizen, even from an English request" do
        citizen.update!(preferred_locale: "ht")
        mail = I18n.with_locale(:en) { Citizens::IdentitySubmissionMailer.public_send(email, submission) }
        expect(mail.subject).to start_with("BonID: ")
        expect(mail.subject).not_to eq(english_subject)
        body = body_of(mail)
        expect(body).to include("Bonjou <strong>Davidson</strong>,", "Ekip BonID")
        expect(body).not_to include(*ENGLISH_MARKERS)
        expect(body).not_to include("translation missing")
      end

      it "is all French for a French-speaking citizen" do
        citizen.update!(preferred_locale: "fr")
        mail = Citizens::IdentitySubmissionMailer.public_send(email, submission)
        expect(mail.subject).to start_with("BonID : ")
        body = body_of(mail)
        expect(body).to include("Bonjour <strong>Davidson</strong>,", "L’équipe BonID")
        expect(body).not_to include("translation missing")
      end
    end
  end

  it "keeps the plain-text part of the received email in the citizen's language" do
    citizen.update!(preferred_locale: "fr")
    mail = Citizens::IdentitySubmissionMailer.submission_received_email(submission)
    expect(mail.text_part.body.decoded).to include("Bonjour Davidson,", "L’équipe BonID")
  end

  describe "QrScanMailer#scan_alert" do
    let(:log) do
      # city/country live on the scan; the log delegates to it
      scan = QrScan.create!(identity_submission: submission, verified_by: "public_camera",
                            city: "Cap-Haïtien", country: "Haiti")
      QrScanLog.create!(qr_scan: scan, identity_submission: submission, scanned_at: Time.zone.local(2026, 11, 27, 14, 5))
    end

    it "uses the citizen's language and date format", :aggregate_failures do
      { "en" => [ "BonID: Your BonID was checked on Nov 27, 2026", "Someone using a phone camera", "Nov 27, 2026 at 2:05 PM" ],
        "fr" => [ "BonID : votre BonID a été vérifié le 27 nov. 2026", "Quelqu’un avec l’appareil photo d’un téléphone", "27 nov. 2026 à 14:05" ],
        "ht" => [ "BonID: Yo verifye BonID ou 27 nov 2026", "Yon moun ki itilize kamera yon telefòn", "27 nov 2026 a 14:05" ] }.each do |locale, (subject, who, at)|
        citizen.update!(preferred_locale: locale)
        mail = Citizens::QrScanMailer.scan_alert(log)
        expect(mail.subject).to eq(subject)
        expect(body_of(mail)).to include(who, at, "Cap-Haïtien, Haiti")
        expect(mail.text_part.body.decoded).to include(who, at)
        expect(body_of(mail)).not_to include("translation missing")
      end
    end
  end

  describe "NameChangeMailer#reverification_required" do
    let(:ncr) { create(:name_change_request, user: citizen) }

    it "uses the citizen's language", :aggregate_failures do
      { "en" => [ "BonID: Your name change is approved. Please verify again", "Name change approved" ],
        "fr" => [ "BonID : changement de nom approuvé. Nouvelle vérification requise", "Changement de nom approuvé" ],
        "ht" => [ "BonID: Chanjman non ou apwouve. Ou dwe verifye ankò", "Chanjman non apwouve" ] }.each do |locale, (subject, heading)|
        citizen.update!(preferred_locale: locale)
        mail = Citizens::NameChangeMailer.with(user: citizen, name_change_request: ncr).reverification_required
        expect(mail.subject).to eq(subject)
        body = body_of(mail)
        expect(body).to include(heading, "<strong>#{ncr.old_full_name}</strong>", "<strong>Jean-Pierre Dupont</strong>")
        expect(body).not_to include("translation missing")
      end
    end

    it "escapes names in the body" do
      ncr.update_columns(new_first_name: "<b>X</b>")
      mail = Citizens::NameChangeMailer.with(user: citizen, name_change_request: ncr).reverification_required
      expect(body_of(mail)).to include("&lt;b&gt;X&lt;/b&gt;")
    end
  end

  describe "consent emails" do
    let(:partner) { create(:partner, :approved, name: "Zèllus", sector: "fintech") }

    it "go out in the citizen's language, not the request's" do
      citizen.update!(preferred_locale: "fr")
      grant = ConsentGrant.create!(citizen: citizen, partner: partner, status: :pending,
                                   requested_scopes: %w[openid profile], granted_scopes: [])
      fr = I18n.with_locale(:fr) { I18n.t("mailers.consent.request_notification.subject", partner_name: "Zèllus") }
      mail = I18n.with_locale(:en) { Citizens::ConsentMailer.with(grant: grant).request_notification }
      expect(mail.subject).to eq(fr)
    end
  end
end
