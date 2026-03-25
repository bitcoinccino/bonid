require 'rails_helper'

RSpec.describe IdentitySubmission, type: :model do
  before do
    # Prevent ActiveStorage / callbacks from interfering
    allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
    allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:ensure_dual_qrs_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, approved: 1, rejected: 2, revoked: 3) }
    it { is_expected.to define_enum_for(:staged_for).with_values(none: 0, bonbin: 1, badbin: 2) }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:id_type).in_array(%w[cin passport]) }
    it { is_expected.to validate_inclusion_of(:submission_type).in_array(%w[initial resubmission reissue]) }
    it { is_expected.to validate_inclusion_of(:reset_request_status).in_array(%w[pending approved rejected]) }

    it "requires a reason when submission_type is reissue" do
      submission = build(:identity_submission, submission_type: "reissue", reason: nil, user: create(:user), partner: create(:partner))
      expect(submission).not_to be_valid
      expect(submission.errors[:reason]).to include("can't be blank")
    end
  end

  describe "callbacks" do
    it "generates a verification token before create" do
      submission = build(:identity_submission, verification_token: nil, user: create(:user), partner: create(:partner))
      submission.save!
      expect(submission.verification_token).to be_present
    end

    it "sets verified_at and expires_at when approved" do
      submission = build(:identity_submission, status: :approved, verified_at: nil, expires_at: nil, user: create(:user), partner: create(:partner))
      submission.save!
      expect(submission.verified_at).to be_present
      expect(submission.expires_at).to be_within(1.minute).of(1.year.from_now)
    end
  end

  describe "#verified?" do
    it "returns true for approved submissions with valid expiration" do
      submission = build(:identity_submission, status: :approved, verified_at: Time.current, expires_at: 1.year.from_now, user: create(:user), partner: create(:partner))
      expect(submission.verified?).to eq(true)
    end

    it "returns false for expired submissions" do
      submission = build(:identity_submission, status: :approved, expires_at: 1.day.ago, user: create(:user), partner: create(:partner))
      expect(submission.verified?).to eq(false)
    end
  end
end
