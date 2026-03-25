# frozen_string_literal: true

require "rails_helper"

RSpec.describe NameChangeRequest, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:reviewed_by).class_name("AdminUser").optional }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, approved: 1, rejected: 2) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:old_first_name) }
    it { is_expected.to validate_presence_of(:old_last_name) }
    it { is_expected.to validate_presence_of(:new_first_name) }
    it { is_expected.to validate_presence_of(:new_last_name) }
    it { is_expected.to validate_presence_of(:reason) }
    it { is_expected.to validate_inclusion_of(:reason).in_array(NameChangeRequest::REASONS.keys) }

    it "requires other_reason when reason is 'other'" do
      request = build(:name_change_request, :other_reason, other_reason: nil)
      expect(request).not_to be_valid
      expect(request.errors[:other_reason]).to include("can't be blank")
    end

    it "does not require other_reason when reason is not 'other'" do
      request = build(:name_change_request, reason: "marriage", other_reason: nil)
      expect(request).to be_valid
    end

    it "requires rejection_reason when status is rejected" do
      request = build(:name_change_request, status: :rejected, rejection_reason: nil)
      expect(request).not_to be_valid
      expect(request.errors[:rejection_reason]).to include("can't be blank")
    end

    it "requires supporting_document on create" do
      request = build(:name_change_request)
      request.supporting_document.purge
      expect(request).not_to be_valid
      expect(request.errors[:supporting_document]).to include("can't be blank")
    end
  end

  describe "callbacks" do
    describe "snapshot_old_name" do
      it "automatically captures the user's current name on creation" do
        user = create(:user, first_name: "Marie", middle_name: "Claudette", last_name: "Pierre")
        request = create(:name_change_request,
                         user: user,
                         new_first_name: "Marie-Anne",
                         new_last_name: "Dupont")

        expect(request.old_first_name).to eq("Marie")
        expect(request.old_middle_name).to eq("Claudette")
        expect(request.old_last_name).to eq("Pierre")
      end
    end

    describe "apply_name_change" do
      it "updates the user's name when approved" do
        user = create(:user, first_name: "Jean", middle_name: nil, last_name: "Louis")
        request = create(:name_change_request,
                         user: user,
                         new_first_name: "Jean-Pierre",
                         new_middle_name: "Marcel",
                         new_last_name: "Dupont")

        request.update!(
          status: :approved,
          reviewed_by: create(:admin_user),
          reviewed_at: Time.current
        )

        user.reload
        expect(user.first_name).to eq("Jean-Pierre")
        expect(user.middle_name).to eq("Marcel")
        expect(user.last_name).to eq("Dupont")
      end

      it "does not update the user's name when rejected" do
        user = create(:user, first_name: "Jean", last_name: "Louis")
        request = create(:name_change_request,
                         user: user,
                         new_first_name: "Pierre",
                         new_last_name: "Dupont")

        request.update!(
          status: :rejected,
          rejection_reason: "Insufficient documentation",
          reviewed_by: create(:admin_user),
          reviewed_at: Time.current
        )

        user.reload
        expect(user.first_name).to eq("Jean")
        expect(user.last_name).to eq("Louis")
      end
    end
  end

  describe "instance methods" do
    let(:request) do
      build(:name_change_request,
            old_first_name: "Jean",
            old_middle_name: "Claude",
            old_last_name: "Pierre",
            new_first_name: "Jean-Pierre",
            new_middle_name: nil,
            new_last_name: "Dupont")
    end

    describe "#old_full_name" do
      it "returns the old full name" do
        expect(request.old_full_name).to eq("Jean Claude Pierre")
      end
    end

    describe "#new_full_name" do
      it "returns the new full name without blank middle name" do
        expect(request.new_full_name).to eq("Jean-Pierre Dupont")
      end
    end

    describe "#reason_label" do
      it "returns the human-readable reason label" do
        request.reason = "marriage"
        expect(request.reason_label).to eq("Marriage / Union")
      end

      it "returns the label for court_order" do
        request.reason = "court_order"
        expect(request.reason_label).to eq("Court Order")
      end
    end
  end

  describe "scopes" do
    describe ".recent_first" do
      it "orders by created_at descending" do
        old_request = create(:name_change_request, created_at: 2.days.ago)
        new_request = create(:name_change_request, created_at: 1.hour.ago)

        results = NameChangeRequest.recent_first
        expect(results.first).to eq(new_request)
        expect(results.last).to eq(old_request)
      end
    end
  end

  describe "REASONS constant" do
    it "includes all expected reasons" do
      expect(NameChangeRequest::REASONS.keys).to contain_exactly("marriage", "court_order", "error", "other")
    end
  end
end
