# frozen_string_literal: true

require "rails_helper"

# Scanning the wallet QR with any phone camera must land on the public
# verification page.
RSpec.describe "Scanning a citizen's wallet QR", type: :request do
  let(:citizen) { create(:user, :with_address, first_name: "Davidson", last_name: "Louis", bonid: "DL-1990-M-OU-P4821-TST") }
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  it "opens the public verification page from the exact URL the QR encodes" do
    qr_url = URI(submission.public_verify_url)
    get "#{qr_url.path}?#{qr_url.query}"

    expect(response).to have_http_status(:redirect), "QR scan returned #{response.status}: #{response.body.to_s[0, 80]}"
    follow_redirect!
    expect(response.body).to include("Valid BonID")
    expect(response.body).to include("Davidson Louis")
  end
end

RSpec.describe "Scanning a QR for a BonID that's no longer valid", type: :request do
  let(:citizen) { create(:user, first_name: "Davidson", bonid: "DL-1990-M-OU-P4821-TST") }
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  it "shows Suspended instead of a generic error" do
    submission.update_columns(status: IdentitySubmission.statuses[:revoked])
    get "/citizens/identity_submissions/verify", params: { verification_token: submission.verification_token }
    follow_redirect!
    expect(response.body).to include("Suspended")
  end

  it "still rejects an unknown code" do
    get "/citizens/identity_submissions/verify", params: { verification_token: "nope" }
    expect(response).to have_http_status(:not_found)
  end
end
