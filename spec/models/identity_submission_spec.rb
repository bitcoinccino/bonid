# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdentitySubmission, type: :model do
  before do
    allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
    allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:generate_secure_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:copy_selfie_to_user_photo)
  end

  # ── Enums ────────────────────────────────────────────────────
  describe "enums" do
    it "defines status enum" do
      expect(IdentitySubmission.statuses).to eq("pending" => 0, "approved" => 1, "rejected" => 2, "revoked" => 3)
    end

    it "defines submission_type enum" do
      expect(IdentitySubmission.submission_types).to eq("initial" => 0, "resubmission" => 1, "reissue" => 2, "visitor" => 3)
    end

    it "defines staged_for enum" do
      expect(IdentitySubmission.staged_fors).to eq("none" => 0, "bonbin" => 1, "badbin" => 2)
    end
  end

  # ── Associations ─────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:partner).optional }
    it { is_expected.to belong_to(:reviewer).class_name("User").optional }
    it { is_expected.to have_many(:qr_scans).dependent(:destroy) }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_inclusion_of(:id_type).in_array(%w[cin passport driver_license voter_id]) }

    it "validates submission_type is a valid value" do
      expect(IdentitySubmission.submission_types.keys).to contain_exactly("initial", "resubmission", "reissue", "visitor")
    end

    it "requires a reason for reissue submissions" do
      submission = build(:identity_submission, submission_type: "reissue", reason: nil)
      expect(submission).not_to be_valid
      expect(submission.errors[:reason]).to include("can't be blank")
    end

    it "requires country_of_residence" do
      submission = build(:identity_submission, country_of_residence: nil)
      expect(submission).not_to be_valid
      expect(submission.errors[:country_of_residence]).to include("can't be blank")
    end
  end

  # ── Callbacks ────────────────────────────────────────────────
  describe "callbacks" do
    it "generates verification token before create" do
      submission = create(:identity_submission, verification_token: nil, country_of_residence: "HT")
      expect(submission.verification_token).to be_present
    end

    it "sets verified_at and expires_at when approved" do
      submission = create(:identity_submission, :approved, country_of_residence: "HT")
      expect(submission.verified_at).to be_present
      expect(submission.expires_at).to be_present
    end
  end

  # ── ID Types ─────────────────────────────────────────────────
  describe "ID_TYPES" do
    it "supports CIN, passport, driver_license, and voter_id" do
      expect(IdentitySubmission::ID_TYPES.keys).to contain_exactly(:cin, :passport, :driver_license, :voter_id)
    end
  end

  # ── Expiry by ID Type ───────────────────────────────────────
  describe "#expiry_duration" do
    it "returns 10 years for CIN" do
      submission = build(:identity_submission, id_type: "cin")
      expect(submission.expiry_duration).to eq(10.years)
    end

    it "returns 5 years for passport" do
      submission = build(:identity_submission, id_type: "passport")
      expect(submission.expiry_duration).to eq(5.years)
    end

    it "defaults to 5 years for unknown types" do
      submission = build(:identity_submission)
      allow(submission).to receive(:id_type).and_return("unknown")
      expect(submission.expiry_duration).to eq(5.years)
    end
  end

  # ── Verification Status ─────────────────────────────────────
  describe "#verified?" do
    it "returns true for approved with valid expiry" do
      submission = build(:identity_submission, status: :approved, verified_at: Time.current, expires_at: 1.year.from_now)
      expect(submission.verified?).to be true
    end

    it "returns false for expired submissions" do
      submission = build(:identity_submission, status: :approved, verified_at: 1.year.ago, expires_at: 1.day.ago)
      expect(submission.verified?).to be false
    end

    it "returns false for pending submissions" do
      submission = build(:identity_submission, status: :pending)
      expect(submission.verified?).to be false
    end
  end

  describe "#qr_expired?" do
    it "returns true when expires_at is in the past" do
      submission = build(:identity_submission, expires_at: 1.day.ago)
      expect(submission.qr_expired?).to be true
    end

    it "returns false when expires_at is in the future" do
      submission = build(:identity_submission, expires_at: 1.day.from_now)
      expect(submission.qr_expired?).to be false
    end
  end

  # ── Diaspora ─────────────────────────────────────────────────
  describe "#diaspora?" do
    it "returns true for non-HT country" do
      submission = build(:identity_submission, country_of_residence: "US")
      expect(submission.diaspora?).to be true
    end

    it "returns false for HT" do
      submission = build(:identity_submission, country_of_residence: "HT")
      expect(submission.diaspora?).to be false
    end

    it "returns false for blank" do
      submission = build(:identity_submission, country_of_residence: nil)
      expect(submission.diaspora?).to be false
    end
  end

  # ── Certificate Number ──────────────────────────────────────
  describe "#certificate_number" do
    it "generates a deterministic certificate number" do
      submission = create(:identity_submission, country_of_residence: "HT")
      cert1 = submission.certificate_number
      cert2 = submission.certificate_number
      expect(cert1).to eq(cert2)
      expect(cert1).to match(/\ABONID-\d{4}-[A-F0-9]{8}\z/)
    end

    it "is unique per submission" do
      s1 = create(:identity_submission, country_of_residence: "HT")
      s2 = create(:identity_submission, country_of_residence: "HT", user: create(:user))
      expect(s1.certificate_number).not_to eq(s2.certificate_number)
    end
  end

  # ── Smart Resubmission ──────────────────────────────────────
  describe "#biometrics_reusable?" do
    let(:submission) do
      build(:identity_submission, :rejected,
        rejection_reason: "blurry_documents",
        metadata: {
          "liveness" => { "passed" => true },
          "face_match" => { "status" => "match", "similarity" => 95.0 }
        })
    end

    it "returns true for document-only rejections with valid biometrics" do
      allow(submission).to receive_message_chain(:selfie, :attached?).and_return(true)
      allow(submission).to receive_message_chain(:selfie, :blob, :present?).and_return(true)
      stub_const("FaceMatchService::SIMILARITY_THRESHOLD", 80.0) unless defined?(FaceMatchService)
      expect(submission.biometrics_reusable?).to be true
    end

    it "returns false for biometric rejection reasons" do
      submission.rejection_reason = "face_mismatch"
      expect(submission.biometrics_reusable?).to be false
    end
  end

  # ── Face Match Helpers ──────────────────────────────────────
  describe "face match helpers" do
    let(:submission) do
      build(:identity_submission, metadata: {
        "face_match" => { "status" => "match", "similarity" => 92.5 }
      })
    end

    it "#face_match_status returns the status" do
      expect(submission.face_match_status).to eq("match")
    end

    it "#face_match_similarity returns the score" do
      expect(submission.face_match_similarity).to eq(92.5)
    end

    it "#face_matched? returns true for match" do
      expect(submission.face_matched?).to be true
    end

    it "#face_match_flagged? returns true for no_match" do
      submission.metadata["face_match"]["status"] = "no_match"
      expect(submission.face_match_flagged?).to be true
    end
  end

  # ── QR Helpers ───────────────────────────────────────────────
  describe "#qr_for" do
    it "returns public QR for citizen role" do
      submission = build(:identity_submission, public_qr_png_base64: "public_data", secure_qr_png_base64: "secure_data")
      expect(submission.qr_for(:citizen)).to eq("public_data")
    end

    it "returns secure QR for officer role" do
      submission = build(:identity_submission, secure_qr_png_base64: "secure_data")
      expect(submission.qr_for(:officer)).to eq("secure_data")
    end
  end

  # ── Document Helpers ─────────────────────────────────────────
  describe "#ready_for_approval?" do
    it "returns true when no documents are missing" do
      submission = build(:identity_submission)
      allow(submission).to receive(:missing_documents).and_return([])
      expect(submission.ready_for_approval?).to be true
    end

    it "returns false when documents are missing" do
      submission = build(:identity_submission)
      allow(submission).to receive(:missing_documents).and_return([ "selfie" ])
      expect(submission.ready_for_approval?).to be false
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    before do
      create(:identity_submission, :approved, country_of_residence: "HT")
      create(:identity_submission, :rejected, country_of_residence: "HT")
      create(:identity_submission, :pending, country_of_residence: "HT")
    end

    it ".approved returns approved submissions" do
      expect(described_class.approved.count).to eq(1)
    end

    it ".pending returns pending submissions" do
      expect(described_class.pending.count).to eq(1)
    end

    it ".rejected returns rejected submissions" do
      expect(described_class.rejected.count).to eq(1)
    end
  end

  # ─────────────────────────────────────────────────────────
  # Double Lock: CIN Document Number Uniqueness
  # ─────────────────────────────────────────────────────────
  describe "Double Lock — CIN uniqueness" do
    let(:existing_user) { create(:user) }
    let(:new_user) { create(:user) }
    let(:document_number) { "1234567890" }

    before do
      # Create an approved submission with a document number
      create(:identity_submission, :approved,
        user: existing_user,
        document_number: document_number,
        id_type: "cin"
      )
    end

    it "blocks a pending submission from another user with the same document number" do
      duplicate = build(:identity_submission,
        user: new_user,
        document_number: document_number,
        id_type: "cin"
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:document_number]).to be_present
    end

    it "blocks when existing submission is still pending" do
      # Replace with a pending one
      IdentitySubmission.where(user: existing_user).destroy_all
      create(:identity_submission, :pending,
        user: existing_user,
        document_number: document_number,
        id_type: "cin"
      )

      duplicate = build(:identity_submission,
        user: new_user,
        document_number: document_number,
        id_type: "cin"
      )
      expect(duplicate).not_to be_valid
    end

    it "allows the same user to resubmit with the same document number after revocation" do
      # Revoke the old submission first (as would happen in a reissue flow)
      IdentitySubmission.where(user: existing_user).update_all(status: :revoked)

      reissue = build(:identity_submission, :reissue,
        user: existing_user,
        document_number: document_number,
        id_type: "cin"
      )
      expect(reissue).to be_valid
    end

    it "allows a different document number from another user" do
      different = build(:identity_submission,
        user: new_user,
        document_number: "9999999999",
        id_type: "cin"
      )
      expect(different).to be_valid
    end
  end

  # ─────────────────────────────────────────────────────────
  # Double Lock: Face Match Helpers
  # ─────────────────────────────────────────────────────────
  describe "Double Lock — face dedup metadata" do
    let(:submission_with_dedup) do
      build(:identity_submission, metadata: {
        "face_dedup" => {
          "duplicate" => true,
          "matched_user_id" => 42,
          "similarity" => 95.3
        },
        "face_match" => {
          "status" => "no_match",
          "similarity" => 45.2
        }
      })
    end

    let(:clean_submission) do
      build(:identity_submission, metadata: {
        "face_dedup" => { "duplicate" => false },
        "face_match" => { "status" => "match", "similarity" => 92.1 }
      })
    end

    it "detects face dedup duplicate flag" do
      dedup = submission_with_dedup.metadata.dig("face_dedup", "duplicate")
      expect(dedup).to be true
    end

    it "detects face 1:1 mismatch" do
      expect(submission_with_dedup.face_match_status).to eq("no_match")
      expect(submission_with_dedup.face_match_flagged?).to be true
    end

    it "returns correct similarity" do
      expect(submission_with_dedup.face_match_similarity).to eq(45.2)
    end

    it "reports clean submission as matched" do
      expect(clean_submission.face_matched?).to be true
      expect(clean_submission.face_match_flagged?).to be false
    end

    it "returns nil for missing face match data" do
      empty = build(:identity_submission, metadata: {})
      expect(empty.face_match_status).to be_nil
      expect(empty.face_matched?).to be false
    end
  end
end
