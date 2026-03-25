require 'rails_helper'

RSpec.describe "BonID Identity Verification Flow", type: :model do
  let(:partner) { create(:partner) }

  it "simulates a user going through full identity lifecycle" do
    # === Step 1: Create user with address and verified identity ===
    user = create(:user, :with_address)
    expect(user.bonid).not_to be_nil

    # === Step 2: Submit pending identity ===
    submission = create(:identity_submission, :pending, user: user, partner: partner)
    expect(submission.status).to eq("pending")

    # === Step 3: Approve submission ===
    submission.update!(status: :approved, verified_at: Time.current, expires_at: 1.year.from_now)
    expect(submission.status).to eq("approved")

    # === Step 4: Simulate rejection flow ===
    rejected = create(:identity_submission, :rejected, user: user, partner: partner)
    expect(rejected.status).to eq("rejected")

    # === Step 5: Resubmission ===
    resub = create(:identity_submission, user: user, partner: partner, submission_type: :resubmission, status: :pending)
    expect(resub.submission_type).to eq("resubmission")
    expect(resub.status).to eq("pending")

    # === Step 6: Reissue ===
    reissue = create(:identity_submission, user: user, partner: partner, submission_type: :reissue, status: :pending, reason: "Lost ID")
    expect(reissue.submission_type).to eq("reissue")
    expect(reissue.status).to eq("pending")
  end
end
