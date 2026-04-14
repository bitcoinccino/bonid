# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  # ── Factory ──────────────────────────────────────────────────
  describe "factory" do
    it "creates a valid user" do
      user = create(:user)
      expect(user).to be_persisted
      expect(user.email).to be_present
    end

    it "creates a verified user with approved identity" do
      # The :verified trait creates an identity_submission which requires
      # selfie attachment and document_number — test the trait indirectly
      user = create(:user)
      allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:generate_secure_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:copy_selfie_to_user_photo)
      allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
      submission = create(:identity_submission, :approved, user: user, bonid: user.bonid)
      expect(submission.status).to eq("approved")
      expect(user.bonid).to eq(submission.bonid)
    end

    it "creates a user with an address" do
      user = create(:user, :with_address)
      expect(user.address).not_to be_nil
      expect(user.address.locality).to eq("Port-au-Prince")
    end
  end

  # ── Associations ─────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to have_one(:address) }
    it { is_expected.to have_many(:identity_submissions).dependent(:destroy) }
    it { is_expected.to have_many(:verification_records).dependent(:destroy) }
    it { is_expected.to have_many(:consent_grants) }
    it { is_expected.to have_many(:name_change_requests).dependent(:destroy) }
    it { is_expected.to belong_to(:partner).optional }
  end

  # ── Enums ────────────────────────────────────────────────────
  describe "enums" do
    it { is_expected.to define_enum_for(:sex).with_values(male: 0, female: 1, other: 2) }
    it { is_expected.to define_enum_for(:marital_status).with_values(single: 0, married: 1, divorced: 2, widowed: 3) }
  end

  # ── Age Calculation ──────────────────────────────────────────
  describe "#age" do
    it "calculates age from date of birth" do
      user = build(:user, dob: 30.years.ago.to_date)
      expect(user.age).to eq(30)
    end

    it "returns nil when dob is nil" do
      user = build(:user, dob: nil)
      expect(user.age).to be_nil
    end

    it "handles birthday not yet passed this year" do
      user = build(:user, dob: Date.new(Date.current.year - 25, 12, 31))
      # If today is before Dec 31, age should be 24
      if Date.current.month < 12 || (Date.current.month == 12 && Date.current.day < 31)
        expect(user.age).to eq(24)
      else
        expect(user.age).to eq(25)
      end
    end
  end

  # ── Full Name ────────────────────────────────────────────────
  describe "#full_name" do
    it "combines first, middle, and last name" do
      user = build(:user, first_name: "Jean", middle_name: "Pierre", last_name: "Louis")
      expect(user.full_name).to include("Jean")
      expect(user.full_name).to include("Pierre")
      expect(user.full_name).to include("Louis")
    end

    it "falls back to email when names are blank" do
      user = build(:user, first_name: nil, middle_name: nil, last_name: nil)
      expect(user.full_name).to eq(user.email)
    end

    it "includes prefix and suffix when present" do
      user = build(:user, first_name: "Jean", last_name: "Louis", prefix: "Dr", suffix: "Jr")
      expect(user.full_name).to include("Dr")
      expect(user.full_name).to include("JR")
    end
  end

  # ── Roles ────────────────────────────────────────────────────
  describe "roles" do
    let(:user) { create(:user) }

    it "assigns citizen role by default" do
      expect(user.citizen?).to be true
    end

    it "can add partner_admin role" do
      partner = create(:partner)
      user.update!(partner: partner)
      user.add_role(:partner_admin)
      expect(user.partner_admin?).to be true
    end

    it "clears role cache on add" do
      user.add_role(:reviewer)
      expect(user.reviewer?).to be true
    end
  end

  # ── Devise Scope ─────────────────────────────────────────────
  describe "#devise_scope" do
    it "returns :citizen for basic users" do
      user = create(:user)
      expect(user.devise_scope).to eq(:citizen)
    end

    it "returns :partner_admin for partner admins" do
      partner = create(:partner)
      user = create(:user, partner: partner)
      user.add_role(:partner_admin)
      expect(user.devise_scope).to eq(:partner_admin)
    end
  end

  # ── Address Helpers ──────────────────────────────────────────
  describe "#formatted_address" do
    it "returns nil without address" do
      user = build(:user)
      expect(user.formatted_address).to be_nil
    end

    it "formats address components" do
      user = create(:user, :with_address)
      expect(user.formatted_address).to include("Port-au-Prince")
    end
  end

  # ── BonID Profile ────────────────────────────────────────────
  describe "#bonid_profile" do
    it "returns profile hash with citizen data" do
      user = create(:user)
      allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:generate_secure_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:copy_selfie_to_user_photo)
      allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
      create(:identity_submission, :approved, user: user, bonid: user.bonid)
      profile = user.bonid_profile
      expect(profile[:bonid]).to be_present
      expect(profile[:first_name]).to eq("Jean")
      expect(profile[:last_name]).to eq("Louis")
      expect(profile[:verification_status]).to eq("approved")
    end
  end

  # ── QR Signature ─────────────────────────────────────────────
  describe "#secure_bonid_signature" do
    it "generates HMAC-SHA256 signature" do
      user = create(:user)
      sig = user.secure_bonid_signature
      expect(sig).to be_a(String)
      expect(sig.length).to eq(64) # SHA256 hex = 64 chars
    end
  end

  describe "#verify_bonid_signature" do
    it "verifies a valid signature" do
      user = create(:user)
      sig = user.secure_bonid_signature
      expect(user.verify_bonid_signature(sig)).to be true
    end

    it "rejects an invalid signature" do
      user = create(:user)
      expect(user.verify_bonid_signature("invalid")).to be false
    end
  end
end
