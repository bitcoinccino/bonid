# frozen_string_literal: true

require "rails_helper"

# CIN is the primary ID path (DIE suspended passport services).
RSpec.describe "Citizens::IdentitySubmissions", type: :request do
  let(:citizen) { create(:user, :profile_complete) }

  def png(name)
    fixture_file_upload(Rails.root.join("spec/fixtures/files/#{name}.png"), "image/png")
  end

  before do
    sign_in citizen, scope: :citizen
    allow(Geocoder).to receive(:search).and_return([])
  end

  describe "POST /citizens/identity_submissions" do
    it "creates a pending CIN submission with front, back, selfie and signature attached" do
      expect {
        post citizens_identity_submissions_path, params: {
          identity_submission: {
            id_type: "cin",
            cin_front: png("cin_front"), cin_back: png("cin_back"),
            selfie: png("selfie"), signature: png("signature")
          }
        }
      }.to change { citizen.identity_submissions.count }.by(1)

      submission = citizen.identity_submissions.last
      expect(submission.status_pending?).to be(true)
      expect(submission.cin_front).to be_attached
      expect(submission.cin_back).to be_attached
      expect(submission.selfie).to be_attached
      expect(submission.signature).to be_attached
    end

    it "does not create a submission without the CIN images" do
      expect {
        post citizens_identity_submissions_path, params: {
          identity_submission: { id_type: "cin", selfie: png("selfie"), signature: png("signature") }
        }
      }.not_to change(IdentitySubmission, :count)

      expect(response).to have_http_status(:unprocessable_entity).or be_redirect
    end
  end

  describe "profile gate" do
    let(:citizen) { create(:user, :with_address) }

    it "sends citizens with an incomplete profile to finish it first" do
      post citizens_identity_submissions_path, params: { identity_submission: { id_type: "cin" } }
      expect(response).to redirect_to(edit_citizens_profile_path)
    end
  end
end
