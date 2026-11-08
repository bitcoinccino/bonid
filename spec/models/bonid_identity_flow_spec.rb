require 'rails_helper'

RSpec.describe "BonID Identity Verification Flow", type: :model do
  let(:partner) { create(:partner) }

  it "simulates a user going through full identity lifecycle" do
    # === Step 1: Create user with address ===
    user = create(:user, :with_address)
    expect(user.bonid).not_to be_nil

    # === Step 2: First submission is rejected ===
    first = create(:identity_submission, :pending, user: user, partner: partner)
    first.update!(status: :rejected, rejection_reason: "blurry_documents")
    expect(first.reload.status).to eq("rejected")

    # === Step 3: Resubmission is allowed and gets approved ===
    resub = create(:identity_submission, user: user, partner: partner, submission_type: :resubmission, status: :pending)
    expect(resub.submission_type).to eq("resubmission")
    resub.update!(status: :approved, verified_at: Time.current, expires_at: 1.year.from_now)
    expect(resub.status).to eq("approved")

    # === Step 4: Only one active submission — a plain new one is blocked ===
    blocked = build(:identity_submission, user: user, partner: partner, status: :pending)
    expect(blocked).not_to be_valid
    expect(blocked.errors[:base]).to include("User already has an active identity submission.")

    # === Step 5: Reissue (e.g. lost ID) bypasses the single-active check ===
    reissue = build(:identity_submission, user: user, partner: partner, submission_type: :reissue, status: :pending, reason: "Lost ID")
    reissue.skip_single_active_check = true
    reissue.save!
    expect(reissue.submission_type).to eq("reissue")
    expect(reissue.status).to eq("pending")
  end
end
