# spec/models/user_and_identity_submission_spec.rb
require 'rails_helper'

RSpec.describe "User & IdentitySubmission Factories", type: :model do
  before(:all) do
    # Seed departments and communes for address
    @department = Department.first || create(:department, id: 1, name: "Ouest", postal_code_prefix: "HT61")
    @arrondissement = Arrondissement.first || create(:arrondissement, id: 1, name: "Port-au-Prince", department: @department)
    @commune = Commune.first || create(:commune, id: 1, name: "Port-au-Prince", arrondissement: @arrondissement, postal_code: "HT6110")
    @section = CommunalSection.first || create(:communal_section, id: 1, name: "1re Section Test", commune: @commune, postal_code: "HT6000")
  end

  context "User factories" do
    it "creates a verified user with address" do
      user = create(:user, :verified, :with_address)

      expect(user.identity_submissions.first.status).to eq("approved")
      expect(user.address).not_to be_nil
      expect(user.address.locality).to eq("Port-au-Prince")
    end

    it "creates a standard user" do
      user = create(:user)
      expect(user.first_name).to eq("Jean")
      expect(user.identity_submissions).to be_empty
    end
  end

  context "IdentitySubmission factories" do
    it "creates a pending submission" do
      submission = create(:identity_submission, :pending)
      expect(submission.status).to eq("pending")
      expect(submission.verified_at).to be_nil
    end

    it "creates an approved submission" do
      submission = create(:identity_submission)
      expect(submission.status).to eq("approved")
      expect(submission.verified_at).not_to be_nil
    end

    it "creates a rejected submission" do
      submission = create(:identity_submission, :rejected)
      expect(submission.status).to eq("rejected")
      expect(submission.rejection_reason).to eq("blurry_id")
    end
  end

  context "Edge cases with traits" do
    it "creates a female, married, verified user with address" do
      user = create(:user, :verified, :with_address, sex: :female, marital_status: :married)
      expect(user.sex).to eq("female")
      expect(user.marital_status).to eq("married")
      expect(user.identity_submissions.first.status).to eq("approved")
    end

    it "creates an expired identity submission" do
      submission = create(:identity_submission, expires_at: 1.day.ago)
      expect(submission.expires_at).to be < Time.current
    end
  end
end
