# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Citizens::IdentitySubmissions", type: :request do
  let(:citizen) { create(:user, :citizen) }
  let(:partner) { create(:partner, verified_at: Time.current) }

  before do
    sign_in citizen, scope: :citizen
    allow_any_instance_of(Citizens::IdentitySubmissionsController)
      .to receive(:set_partner).and_return(partner)
  end

  describe "POST /citizens/identity_submissions" do
    context "with valid file uploads" do
      let(:valid_files) do
        {
          id_type: "passport",
          selfie: fixture_file_upload(Rails.root.join("spec/fixtures/files/selfie.jpg"), "image/jpeg"),
          passport: fixture_file_upload(Rails.root.join("spec/fixtures/files/passport.jpg"), "image/jpeg"),
          signature: fixture_file_upload(Rails.root.join("spec/fixtures/files/signature.png"), "image/png"),
          proof_of_address: fixture_file_upload(Rails.root.join("spec/fixtures/files/bill.png"), "image/png")
        }
      end

      it "creates a pending submission with all attachments" do
        post citizens_identity_submissions_path, params: { identity_submission: valid_files }

        expect(response).to redirect_to(citizens_identity_submissions_path)
        submission = citizen.identity_submissions.last
        expect(submission).to be_present
        expect(submission.status_pending?).to eq(true)

        # Check that all files are attached
        expect(submission.selfie).to be_attached
        expect(submission.passport).to be_attached
        expect(submission.signature).to be_attached
        expect(submission.proof_of_address).to be_attached
      end
    end

    context "with drawn signature (base64)" do
      let(:base64_signature) do
        "data:image/png;base64," + Base64.strict_encode64(File.read(Rails.root.join("spec/fixtures/files/signature.png")))
      end

      let(:valid_files_with_drawn_signature) do
        {
          id_type: "cin",
          cin_front: fixture_file_upload(Rails.root.join("spec/fixtures/files/cin_front.jpg"), "image/jpeg"),
          cin_back: fixture_file_upload(Rails.root.join("spec/fixtures/files/cin_back.jpg"), "image/jpeg"),
          selfie: fixture_file_upload(Rails.root.join("spec/fixtures/files/selfie.jpg"), "image/jpeg"),
          signature_drawn: base64_signature
        }
      end

      it "creates submission and attaches signature from base64" do
        post citizens_identity_submissions_path, params: { identity_submission: valid_files_with_drawn_signature }

        submission = citizen.identity_submissions.last
        expect(submission).to be_present
        expect(submission.signature).to be_attached
      end
    end

    context "with missing mandatory files" do
      it "fails and shows validation error" do
        post citizens_identity_submissions_path, params: { identity_submission: { id_type: "passport" } }
        expect(response.body).to include("Please recheck your signature or uploaded files")
      end
    end
  end

  describe "PATCH /citizens/identity_submissions/:id" do
    let(:submission) { create(:identity_submission, user: citizen, partner: partner, status: :pending) }

    it "updates the submission successfully" do
      patch citizens_identity_submission_path(submission),
            params: { identity_submission: { proof_of_address: fixture_file_upload(Rails.root.join("spec/fixtures/files/bill.png"), "image/png") } }

      expect(response).to redirect_to(citizens_identity_submission_path(submission))
      expect(submission.reload.proof_of_address).to be_attached
    end
  end
end
