# frozen_string_literal: true

require "rails_helper"

# The public page anyone sees after scanning a citizen's wallet QR.
# It must confirm identity with the minimum personal data.
RSpec.describe "Public BonID verification page", type: :request do
  let(:citizen) do
    create(:user, :with_address, first_name: "Davidson", last_name: "Louis",
           bonid: "DL-1990-M-OU-P4821-TST", dob: "1990-03-14")
  end
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  def visit_page(sub = submission)
    get "/citizens/identity_submissions/#{sub.public_token}/verified_profile"
  end

  it "opens without logging in" do
    visit_page
    expect(response).to have_http_status(:ok)
  end

  context "valid BonID" do
    before { visit_page }

    it "shows the name, a Valid badge and the masked BonID" do
      expect(response.body).to include("Davidson Louis")
      expect(response.body).to include("Valid BonID")
      expect(response.body).to include("DL-****-*-**-821TST")
    end

    it "never shows the full BonID or its CIN digits" do
      expect(response.body).not_to include("DL-1990-M-OU-P4821-TST")
      expect(response.body).not_to include("4821")
    end

    it "never shows date of birth or home address" do
      expect(response.body).not_to include("1990-03-14")
      expect(response.body).not_to include("14/03/1990")
      expect(response.body).not_to include("March 14, 1990")
      expect(response.body).not_to include(citizen.formatted_address.to_s) if citizen.formatted_address.present?
    end

    it "doesn't show internal codes" do
      expect(response.body).not_to include(submission.verification_token)
      expect(response.body).not_to include("Invalid Signature")
      expect(response.body).not_to include("Checksum")
    end

    it "asks search engines not to index it" do
      expect(response.headers["X-Robots-Tag"]).to include("noindex")
    end
  end

  describe "photo" do
    let(:png) { Rack::Test::UploadedFile.new(StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")), "image/png", original_filename: "p.png") }
  
    it "never falls back to the editable profile photo" do
      submission.selfie.purge if submission.selfie.attached?
      citizen.photo.attach(io: StringIO.new(png.read), filename: "profile.png", content_type: "image/png")
      visit_page
      expect(response.body).not_to include("profile.png")
      expect(response.body).to include("No verified photo on file")
    end
  end
  
  it "shows Expired with the date, still with name for the person checking" do
    submission.update_columns(expires_at: Date.new(2026, 1, 5).to_time)
    visit_page
    expect(response.body).to include("Expired")
    expect(response.body).to include("Jan 5, 2026") # card_date, same as the wallet card
    expect(response.body).to include("Davidson Louis")
  end

  it "shows Suspended and no personal details when revoked" do
    submission.update_columns(status: IdentitySubmission.statuses[:revoked])
    visit_page
    expect(response.body).to include("Suspended")
    expect(response.body).not_to include("Davidson")
  end

  it "shows Not valid and no personal details when not yet verified" do
    pending_sub = create(:identity_submission, user: create(:user, first_name: "Pending", bonid: "PN-1990-M-OU-P0000-ABC"))
    visit_page(pending_sub)
    expect(response.body).to include("Not valid")
    expect(response.body).not_to include("Pending")
  end

  it "returns 404 for an unknown token" do
    get "/citizens/identity_submissions/not-a-real-token/verified_profile"
    expect(response).to have_http_status(:not_found)
  end
end
