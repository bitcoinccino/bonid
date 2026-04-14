# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReviewerActivity, type: :model do
  let(:reviewer) { create(:user) }
  let(:submission) { create(:identity_submission, :pending) }

  before do
    reviewer.add_role(:reviewer)
  end

  # ─────────────────────────────────────────────────────────
  # Associations
  # ─────────────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:target).optional }
  end

  # ─────────────────────────────────────────────────────────
  # Validations
  # ─────────────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:action) }
    it { is_expected.to validate_inclusion_of(:action).in_array(ReviewerActivity::ACTIONS) }

    it "rejects invalid actions" do
      activity = build(:reviewer_activity, user: reviewer, action: "hack_system")
      expect(activity).not_to be_valid
      expect(activity.errors[:action]).to be_present
    end

    it "accepts all valid actions" do
      ReviewerActivity::ACTIONS.each do |action|
        activity = build(:reviewer_activity, user: reviewer, action: action)
        expect(activity).to be_valid
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  # ACTIONS constant
  # ─────────────────────────────────────────────────────────
  describe "ACTIONS" do
    it "includes all expected actions" do
      expect(ReviewerActivity::ACTIONS).to contain_exactly(
        "login", "logout", "view_submission", "approve", "reject", "override_warning"
      )
    end
  end

  # ─────────────────────────────────────────────────────────
  # Scopes
  # ─────────────────────────────────────────────────────────
  describe "scopes" do
    let!(:login_activity) do
      ReviewerActivity.log!(user: reviewer, action: "login", ip_address: "1.2.3.4")
    end
    let!(:view_activity) do
      ReviewerActivity.log!(user: reviewer, action: "view_submission", target: submission)
    end
    let!(:approve_activity) do
      ReviewerActivity.log!(user: reviewer, action: "approve", target: submission)
    end
    let!(:reject_activity) do
      ReviewerActivity.log!(user: reviewer, action: "reject", target: submission)
    end
    let!(:override_activity) do
      ReviewerActivity.log!(user: reviewer, action: "override_warning", target: submission,
                            metadata: { warning_type: "duplicate_identity" })
    end

    describe ".logins" do
      it "returns only login events" do
        expect(ReviewerActivity.logins).to contain_exactly(login_activity)
      end
    end

    describe ".reviews" do
      it "returns approve and reject events" do
        expect(ReviewerActivity.reviews).to contain_exactly(approve_activity, reject_activity)
      end
    end

    describe ".approvals" do
      it "returns only approve events" do
        expect(ReviewerActivity.approvals).to contain_exactly(approve_activity)
      end
    end

    describe ".rejections" do
      it "returns only reject events" do
        expect(ReviewerActivity.rejections).to contain_exactly(reject_activity)
      end
    end

    describe ".overrides" do
      it "returns only override_warning events" do
        expect(ReviewerActivity.overrides).to contain_exactly(override_activity)
      end
    end

    describe ".views" do
      it "returns only view_submission events" do
        expect(ReviewerActivity.views).to contain_exactly(view_activity)
      end
    end

    describe ".today" do
      it "includes activities from today" do
        expect(ReviewerActivity.today.count).to eq(5)
      end

      it "excludes activities from yesterday" do
        old = ReviewerActivity.log!(user: reviewer, action: "login")
        old.update_column(:created_at, 2.days.ago)
        expect(ReviewerActivity.today).not_to include(old)
      end
    end

    describe ".last_30_days" do
      it "includes activities from last 30 days" do
        expect(ReviewerActivity.last_30_days.count).to eq(5)
      end

      it "excludes activities older than 30 days" do
        old = ReviewerActivity.log!(user: reviewer, action: "login")
        old.update_column(:created_at, 31.days.ago)
        expect(ReviewerActivity.last_30_days).not_to include(old)
      end
    end

    describe ".for_reviewer" do
      let(:other_reviewer) { create(:user) }

      before { other_reviewer.add_role(:reviewer) }

      it "returns only activities for the specified reviewer" do
        other_activity = ReviewerActivity.log!(user: other_reviewer, action: "login")
        expect(ReviewerActivity.for_reviewer(reviewer.id)).not_to include(other_activity)
        expect(ReviewerActivity.for_reviewer(other_reviewer.id)).to contain_exactly(other_activity)
      end
    end

    describe ".for_submission" do
      it "returns activities targeting the given submission" do
        results = ReviewerActivity.for_submission(submission)
        expect(results).to include(view_activity, approve_activity, reject_activity, override_activity)
        expect(results).not_to include(login_activity)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        results = ReviewerActivity.recent.to_a
        expect(results).to eq(results.sort_by(&:created_at).reverse)
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  # .log!
  # ─────────────────────────────────────────────────────────
  describe ".log!" do
    it "creates a new activity record" do
      expect {
        ReviewerActivity.log!(user: reviewer, action: "login", ip_address: "10.0.0.1")
      }.to change(ReviewerActivity, :count).by(1)
    end

    it "stores metadata as JSONB" do
      activity = ReviewerActivity.log!(
        user: reviewer,
        action: "approve",
        target: submission,
        metadata: { status_before: "pending", status_after: "approved", review_duration: 45 }
      )
      expect(activity.metadata["status_before"]).to eq("pending")
      expect(activity.metadata["review_duration"]).to eq(45)
    end

    it "associates polymorphic target" do
      activity = ReviewerActivity.log!(
        user: reviewer,
        action: "view_submission",
        target: submission
      )
      expect(activity.target).to eq(submission)
      expect(activity.target_type).to eq("IdentitySubmission")
    end

    it "stores IP address" do
      activity = ReviewerActivity.log!(
        user: reviewer,
        action: "login",
        ip_address: "192.168.1.1"
      )
      expect(activity.ip_address).to eq("192.168.1.1")
    end
  end

  # ─────────────────────────────────────────────────────────
  # .review_duration_for
  # ─────────────────────────────────────────────────────────
  describe ".review_duration_for" do
    it "calculates seconds between view and decision" do
      view = ReviewerActivity.log!(user: reviewer, action: "view_submission", target: submission)
      view.update_column(:created_at, 90.seconds.ago)

      decision = ReviewerActivity.log!(user: reviewer, action: "approve", target: submission)

      duration = ReviewerActivity.review_duration_for(reviewer.id, submission)
      expect(duration).to be_within(5).of(90)
    end

    it "returns nil when no view event exists" do
      ReviewerActivity.log!(user: reviewer, action: "approve", target: submission)
      duration = ReviewerActivity.review_duration_for(reviewer.id, submission)
      expect(duration).to be_nil
    end
  end
end
