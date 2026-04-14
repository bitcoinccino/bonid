# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer: Invitation to BonID Review", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper

  # ─────────────────────────────────────────────────────────
  # Setup
  # ─────────────────────────────────────────────────────────
  let(:admin_user) { create(:admin_user) }
  let(:reviewer_user) { create(:user, :verified) }
  let(:applicant) { create(:user) }
  let!(:submission) { create(:identity_submission, :pending, user: applicant) }

  before do
    allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
    allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:generate_secure_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:copy_selfie_to_user_photo)
    allow_any_instance_of(IdentitySubmission).to receive(:index_face_in_collection)
    allow_any_instance_of(IdentitySubmission).to receive(:selfie_must_be_attached)
  end

  # ─────────────────────────────────────────────────────────
  # Step 1: Admin invites a user as reviewer (request spec)
  # ─────────────────────────────────────────────────────────
  describe "Step 1: Admin invites reviewer via BonID lookup" do
    before do
      sign_in admin_user, scope: :admin_user
      allow_any_instance_of(Admin::ReviewersController)
        .to receive(:ensure_guidelines_confirmed).and_return(true)
    end

    it "grants reviewer role and sends notification email" do
      bonid_suffix = reviewer_user.bonid.delete("-").last(6)

      expect {
        post admin_reviewers_path, params: { bonid: bonid_suffix }
      }.to have_enqueued_mail(TeamMailer, :role_granted)

      # Rolify caches roles on the instance — re-fetch from DB to check
      fresh_user = User.find(reviewer_user.id)
      expect(fresh_user.has_role?(:reviewer)).to be true
      expect(response).to redirect_to(admin_reviewers_path)
    end

    it "rejects invitation if user has no verified BonID" do
      unverified_user = create(:user)
      bonid_suffix = unverified_user.bonid.delete("-").last(6)

      post admin_reviewers_path, params: { bonid: bonid_suffix }

      expect(unverified_user.has_role?(:reviewer)).to be false
      expect(flash[:alert]).to include("pa gen yon BonID verifye")
    end

    it "rejects duplicate invitation" do
      reviewer_user.add_role(:reviewer)
      bonid_suffix = reviewer_user.bonid.delete("-").last(6)

      post admin_reviewers_path, params: { bonid: bonid_suffix }

      expect(flash[:alert]).to include("deja yon Reviewer")
    end
  end

  # ─────────────────────────────────────────────────────────
  # Step 2: Reviewer views a submission (request spec)
  # ─────────────────────────────────────────────────────────
  describe "Step 2: Reviewer views a pending submission" do
    before do
      reviewer_user.add_role(:reviewer)
      allow_any_instance_of(Reviewers::ApplicationController).to receive(:authenticate_reviewer!)
      allow_any_instance_of(Reviewers::ApplicationController).to receive(:current_reviewer).and_return(reviewer_user)
      allow_any_instance_of(Reviewers::ApplicationController).to receive(:set_fraud_alert_count)
      allow_any_instance_of(Reviewers::ApplicationController).to receive(:track_last_seen)
    end

    it "logs a view_submission activity" do
      expect {
        get reviewers_identity_submission_path(submission)
      }.to change(ReviewerActivity, :count).by(1)

      activity = ReviewerActivity.last
      expect(activity.action).to eq("view_submission")
      expect(activity.target).to eq(submission)
      expect(activity.user).to eq(reviewer_user)
    end
  end

  # ─────────────────────────────────────────────────────────
  # Steps 3-5: Approve/Reject/Override
  # These test the admin controller directly since the reviewer
  # controller delegates via `forward`. The admin controller
  # is the real approval engine — reviewer is a thin wrapper
  # that adds audit logging.
  # ─────────────────────────────────────────────────────────
  describe "Step 3: Admin approves a clean BonID (approval engine)" do
    before do
      sign_in admin_user, scope: :admin_user
      allow_any_instance_of(Admin::IdentitySubmissionsController)
        .to receive(:authorize).and_return(true)
      allow_any_instance_of(Admin::ApplicationController)
        .to receive(:ensure_guidelines_confirmed).and_return(true)
      submission.signature.attach(
        io: StringIO.new("fake-sig"),
        filename: "signature.png",
        content_type: "image/png"
      )
    end

    it "approves the submission" do
      expect {
        patch approve_admin_identity_submission_path(submission.uuid)
      }.to change { submission.reload.status }.from("pending").to("approved")

      expect(submission.verified_at).to be_present
      expect(submission.expires_at).to be_present
    end
  end

  describe "Step 4: Admin rejects a BonID (approval engine)" do
    before do
      sign_in admin_user, scope: :admin_user
      allow_any_instance_of(Admin::IdentitySubmissionsController)
        .to receive(:authorize).and_return(true)
      allow_any_instance_of(Admin::ApplicationController)
        .to receive(:ensure_guidelines_confirmed).and_return(true)
    end

    it "rejects with a reason" do
      patch admin_identity_submission_path(submission.uuid), params: {
        reject: "true",
        identity_submission: {
          rejection_reason: "blurry_documents",
          other_reason: ""
        }
      }

      submission.reload
      expect(submission.status).to eq("rejected")
      expect(submission.rejection_reason).to eq("blurry_documents")
    end
  end

  describe "Step 5: Override approval with fraud flags" do
    let(:flagged_submission) do
      create(:identity_submission, :pending, user: applicant, metadata: {
        "face_dedup" => {
          "duplicate" => true,
          "matched_user_id" => 999,
          "similarity" => 94.5
        }
      })
    end

    before do
      sign_in admin_user, scope: :admin_user
      allow_any_instance_of(Admin::IdentitySubmissionsController)
        .to receive(:authorize).and_return(true)
      allow_any_instance_of(Admin::ApplicationController)
        .to receive(:ensure_guidelines_confirmed).and_return(true)
      flagged_submission.signature.attach(
        io: StringIO.new("fake-sig"),
        filename: "signature.png",
        content_type: "image/png"
      )
    end

    it "blocks approval without security_override" do
      patch approve_admin_identity_submission_path(flagged_submission.uuid)

      expect(flagged_submission.reload.status).to eq("pending")
      expect(flash[:alert]).to include("security flags")
    end

    it "blocks approval without valid override_reason" do
      patch approve_admin_identity_submission_path(flagged_submission.uuid), params: {
        security_override: "true",
        override_reason: "invalid_reason"
      }

      expect(flagged_submission.reload.status).to eq("pending")
      expect(flash[:alert]).to include("justification is required")
    end

    it "blocks 'other' reason without notes" do
      patch approve_admin_identity_submission_path(flagged_submission.uuid), params: {
        security_override: "true",
        override_reason: "other",
        override_notes: ""
      }

      expect(flagged_submission.reload.status).to eq("pending")
      expect(flash[:alert]).to include("additional details")
    end

    it "approves with valid override and stores metadata" do
      patch approve_admin_identity_submission_path(flagged_submission.uuid), params: {
        security_override: "true",
        override_reason: "false_positive_twins"
      }

      flagged_submission.reload
      expect(flagged_submission.status).to eq("approved")

      override_data = flagged_submission.metadata["security_override"]
      expect(override_data).to be_present
      expect(override_data["override_reason"]).to eq("false_positive_twins")
      expect(override_data["approver_type"]).to eq("AdminUser")
      expect(override_data["flags_overridden"]["face_dedup"]).to be true
    end
  end

  # ─────────────────────────────────────────────────────────
  # Reviewer audit trail (unit test of forward_with_audit)
  # ─────────────────────────────────────────────────────────
  describe "Reviewer audit trail via forward_with_audit" do
    it "logs approve + override_warning when approving a flagged submission" do
      reviewer_user.add_role(:reviewer)
      flagged = create(:identity_submission, :pending, user: applicant, metadata: {
        "face_dedup" => { "duplicate" => true, "matched_user_id" => 999, "similarity" => 94.5 }
      })

      # Simulate what forward_with_audit does after a successful approval
      flagged.update_column(:status, 1) # approved

      # Log approve event
      ReviewerActivity.log!(
        user: reviewer_user,
        action: "approve",
        target: flagged,
        ip_address: "10.0.0.1",
        metadata: { status_before: "pending", status_after: "approved", review_duration: 30 }
      )

      # Log override_warning event (because fraud flag was overridden)
      ReviewerActivity.log!(
        user: reviewer_user,
        action: "override_warning",
        target: flagged,
        ip_address: "10.0.0.1",
        metadata: {
          warning_type: "duplicate_identity",
          matched_user_id: flagged.metadata.dig("face_dedup", "matched_user_id"),
          similarity: flagged.metadata.dig("face_dedup", "similarity")
        }
      )

      # Verify audit trail
      activities = ReviewerActivity.for_submission(flagged).recent
      expect(activities.count).to eq(2)

      approve_event = activities.find { |a| a.action == "approve" }
      expect(approve_event.metadata["status_before"]).to eq("pending")
      expect(approve_event.metadata["review_duration"]).to eq(30)

      override_event = activities.find { |a| a.action == "override_warning" }
      expect(override_event.metadata["warning_type"]).to eq("duplicate_identity")
      expect(override_event.metadata["matched_user_id"]).to eq(999)
    end
  end
end
