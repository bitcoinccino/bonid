# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BonID → VoterEligibilityRecord Handoff", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  before do
    allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
    allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:generate_secure_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:copy_selfie_to_user_photo)
    allow_any_instance_of(IdentitySubmission).to receive(:index_face_in_collection)
    allow_any_instance_of(IdentitySubmission).to receive(:selfie_must_be_attached)
    # Diaspora submissions require host_country docs — stub for voter registration tests
    allow_any_instance_of(IdentitySubmission).to receive(:validate_host_country_id_attached)
  end

  let(:election) { create(:bonvote_election, :open) }
  let(:face_id) { "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }

  # Shared metadata with Rekognition face_id enrolled
  let(:face_metadata) do
    {
      "face_collection" => {
        "face_id" => face_id,
        "indexed_at" => Time.current.iso8601,
        "collection_id" => "bonid-verified-faces"
      },
      "face_match" => { "status" => "match", "similarity" => 98.5 }
    }
  end

  # ─────────────────────────────────────────────────────────
  # 1. Domestic Path (Haiti) — Full Ballot
  # ─────────────────────────────────────────────────────────
  describe "Domestic voter (Haiti)" do
    let(:citizen) { create(:user, :domestic, dob: 30.years.ago) }
    let!(:submission) do
      create(:identity_submission, :approved,
        user: citizen,
        country_of_residence: "HT",
        metadata: face_metadata
      )
    end

    it "registers as eligible with domestic channel" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record).to be_eligible
      expect(record.channel).to eq("domestic")
    end

    it "pulls department_code from address (not country code)" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record.department_code).to eq("ouest")
    end

    it "stores biometric fingerprint from Rekognition face_id" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expected_hash = OpenSSL::Digest::SHA256.hexdigest(face_id)
      expect(record.biometric_fingerprint).to eq(expected_hash)
    end

    it "gets a full ballot (president + senator + deputy)" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      # Domestic voters get constituency from election (or dept fallback)
      expect(record.constituency_name).not_to eq("Dyaspora")
      expect(record.commune_id).to be_present
    end
  end

  # ─────────────────────────────────────────────────────────
  # 2. Diaspora Path (Abroad) — President-Only Ballot
  # ─────────────────────────────────────────────────────────
  describe "Diaspora voter (abroad)" do
    let(:citizen_us) { create(:user, :diaspora, dob: 30.years.ago) }
    let!(:submission_us) do
      create(:identity_submission, :approved,
        user: citizen_us,
        country_of_residence: "US",
        host_country_id_type: "passport",
        metadata: face_metadata
      )
    end

    let(:citizen_fr) { create(:user, :diaspora, dob: 28.years.ago) }
    let!(:submission_fr) do
      create(:identity_submission, :approved,
        user: citizen_fr,
        country_of_residence: "FR",
        host_country_id_type: "passport",
        metadata: face_metadata.merge(
          "face_collection" => { "face_id" => "11111111-2222-3333-4444-555555555555" }
        )
      )
    end

    it "registers as eligible with diaspora channel" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen_us)

      expect(record).to be_eligible
      expect(record.channel).to eq("diaspora")
    end

    it "uses ISO country code as department_code (US)" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen_us)

      expect(record.department_code).to eq("US")
    end

    it "uses ISO country code as department_code (FR)" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen_fr)

      expect(record.department_code).to eq("FR")
    end

    it "assigns Dyaspora constituency (president-only ballot)" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen_us)

      expect(record.constituency_name).to eq("Dyaspora")
    end

    it "has no commune_id (no local district)" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen_us)

      expect(record.commune_id).to be_nil
    end

    it "stores biometric fingerprint same as domestic" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen_us)

      expected_hash = OpenSSL::Digest::SHA256.hexdigest(face_id)
      expect(record.biometric_fingerprint).to eq(expected_hash)
    end

    it "produces different fingerprints for different voters" do
      record_us = VoterEligibilityRecord.register_voter!(election: election, user: citizen_us)
      record_fr = VoterEligibilityRecord.register_voter!(election: election, user: citizen_fr)

      expect(record_us.biometric_fingerprint).not_to eq(record_fr.biometric_fingerprint)
    end
  end

  # ─────────────────────────────────────────────────────────
  # 3. Biometric Anchor & Voter Key Derivation
  # ─────────────────────────────────────────────────────────
  describe "biometric anchor in voter key derivation" do
    let(:citizen) { create(:user, :domestic, dob: 30.years.ago) }
    let!(:submission) do
      create(:identity_submission, :approved,
        user: citizen,
        country_of_residence: "HT",
        metadata: face_metadata
      )
    end

    it "biometric_anchor returns fingerprint when face_id enrolled" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record.biometric_anchor).to eq(record.biometric_fingerprint)
    end

    it "biometric_anchor falls back to BonID hash for pre-Rekognition accounts" do
      # No face_collection in metadata
      submission.update_column(:metadata, {})

      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record.biometric_fingerprint).to be_nil
      expect(record.biometric_anchor).to eq(OpenSSL::Digest::SHA256.hexdigest(citizen.bonid.to_s))
    end

    it "different biometric anchors produce different voter keys" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      liveness_id = SecureRandom.uuid
      liveness_bio = SecureRandom.hex(32)

      # Real anchor (face_id hash)
      combined_real = OpenSSL::Digest::SHA256.hexdigest("#{liveness_bio}||#{record.biometric_anchor}")
      key_real = ::Election::EligibilityProofService.derive_voter_key(citizen.bonid, liveness_id, combined_real)

      # Fake anchor (attacker guessing)
      combined_fake = OpenSSL::Digest::SHA256.hexdigest("#{liveness_bio}||fake_anchor")
      key_fake = ::Election::EligibilityProofService.derive_voter_key(citizen.bonid, liveness_id, combined_fake)

      expect(key_real).not_to eq(key_fake)
    end

    it "same voter + same biometric = same nullifier (deterministic)" do
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      bio = "consistent-liveness"
      combined = OpenSSL::Digest::SHA256.hexdigest("#{bio}||#{record.biometric_anchor}")

      key1 = ::Election::EligibilityProofService.derive_voter_key(citizen.bonid, "session-A", combined)
      key2 = ::Election::EligibilityProofService.derive_voter_key(citizen.bonid, "session-A", combined)

      nullifier1 = ::Election::EligibilityProofService.generate_nullifier(key1, election.id.to_s)
      nullifier2 = ::Election::EligibilityProofService.generate_nullifier(key2, election.id.to_s)

      expect(nullifier1).to eq(nullifier2)
    end
  end

  # ─────────────────────────────────────────────────────────
  # 4. Ineligibility Rules
  # ─────────────────────────────────────────────────────────
  describe "ineligibility determination" do
    it "rejects user without approved submission" do
      user = create(:user, :domestic, dob: 25.years.ago)
      create(:identity_submission, :pending, user: user, country_of_residence: "HT")

      record = VoterEligibilityRecord.register_voter!(election: election, user: user)

      expect(record).not_to be_eligible
      expect(record.ineligibility_reason).to eq("no_cin")
    end

    it "rejects underage user" do
      user = create(:user, :domestic, dob: 16.years.ago)
      create(:identity_submission, :approved, user: user, country_of_residence: "HT")

      record = VoterEligibilityRecord.register_voter!(election: election, user: user)

      expect(record).not_to be_eligible
      expect(record.ineligibility_reason).to eq("underage")
    end

    it "rejects user with expired identity" do
      user = create(:user, :domestic, dob: 25.years.ago)
      create(:identity_submission, :approved,
        user: user,
        country_of_residence: "HT",
        expires_at: 1.day.ago
      )

      record = VoterEligibilityRecord.register_voter!(election: election, user: user)

      expect(record).not_to be_eligible
      expect(record.ineligibility_reason).to eq("expired_id")
    end

    it "rejects user with no BonID" do
      user = create(:user, :domestic, dob: 25.years.ago, bonid: nil)

      # bonid is blank so register_voter! sets ineligible, but
      # validation still requires bonid presence — save! raises
      expect {
        VoterEligibilityRecord.register_voter!(election: election, user: user)
      }.to raise_error(ActiveRecord::RecordInvalid, /Bonid/)
    end
  end

  # ─────────────────────────────────────────────────────────
  # 5. Idempotency & Bulk Import
  # ─────────────────────────────────────────────────────────
  describe "idempotency" do
    let(:citizen) { create(:user, :domestic, dob: 25.years.ago) }
    let!(:submission) do
      create(:identity_submission, :approved, user: citizen, country_of_residence: "HT")
    end

    it "returns existing record on duplicate call" do
      record1 = VoterEligibilityRecord.register_voter!(election: election, user: citizen)
      record2 = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record1.id).to eq(record2.id)
      expect(VoterEligibilityRecord.where(user: citizen, bonvote_election: election).count).to eq(1)
    end
  end

  describe ".build_electoral_list!" do
    before do
      # 2 domestic eligible voters
      2.times do
        u = create(:user, :domestic, dob: 25.years.ago)
        create(:identity_submission, :approved, user: u, country_of_residence: "HT")
      end
      # 1 diaspora eligible voter
      u = create(:user, :diaspora, dob: 25.years.ago)
      create(:identity_submission, :approved, user: u, country_of_residence: "US", host_country_id_type: "passport")
    end

    it "imports all verified BonID holders" do
      expect {
        VoterEligibilityRecord.build_electoral_list!(election: election)
      }.to change(VoterEligibilityRecord, :count).by_at_least(3)
    end

    it "creates both domestic and diaspora records" do
      VoterEligibilityRecord.build_electoral_list!(election: election)

      expect(VoterEligibilityRecord.domestic.count).to be >= 2
      expect(VoterEligibilityRecord.diaspora.count).to be >= 1
    end
  end

  # ─────────────────────────────────────────────────────────
  # 6. End-to-End: BonID Approval → Voter Roll → ZKP
  # ─────────────────────────────────────────────────────────
  describe "end-to-end: identity verification to vote readiness" do
    let(:citizen) { create(:user, :domestic, dob: 30.years.ago) }

    it "domestic: full chain from BonID approval to ZKP verification" do
      # Step 1: BonID approved with face indexed
      create(:identity_submission, :approved,
        user: citizen,
        country_of_residence: "HT",
        metadata: face_metadata
      )

      # Step 2: CEP registers voter
      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)
      expect(record).to be_eligible
      expect(record.channel).to eq("domestic")
      expect(record.biometric_fingerprint).to be_present

      # Step 3: Voter key derived with biometric anchor
      liveness_session = SecureRandom.uuid
      liveness_bio = SecureRandom.hex(32)
      combined = OpenSSL::Digest::SHA256.hexdigest("#{liveness_bio}||#{record.biometric_anchor}")

      voter_key = ::Election::EligibilityProofService.derive_voter_key(
        citizen.bonid, liveness_session, combined
      )

      # Step 4: Deterministic nullifier
      nullifier = ::Election::EligibilityProofService.generate_nullifier(voter_key, election.id.to_s)
      expect(nullifier).to be_a(String)
      expect(nullifier.length).to eq(64)

      # Step 5: ZKP proves eligibility
      proof = ::Election::EligibilityProofService.generate_proof(voter_key, election.id.to_s, nullifier)
      verified = ::Election::EligibilityProofService.verify_proof(
        proof, election.id.to_s, nullifier, Set.new([nullifier])
      )
      expect(verified).to be true
    end

    it "diaspora: full chain with country code as department" do
      diaspora_citizen = create(:user, :diaspora, dob: 30.years.ago)
      create(:identity_submission, :approved,
        user: diaspora_citizen,
        country_of_residence: "CA",
        host_country_id_type: "passport",
        metadata: face_metadata
      )

      record = VoterEligibilityRecord.register_voter!(election: election, user: diaspora_citizen)

      expect(record).to be_eligible
      expect(record.channel).to eq("diaspora")
      expect(record.department_code).to eq("CA")
      expect(record.constituency_name).to eq("Dyaspora")

      # Voter key still works
      combined = OpenSSL::Digest::SHA256.hexdigest("liveness||#{record.biometric_anchor}")
      voter_key = ::Election::EligibilityProofService.derive_voter_key(
        diaspora_citizen.bonid, "session-1", combined
      )
      nullifier = ::Election::EligibilityProofService.generate_nullifier(voter_key, election.id.to_s)
      expect(::Election::EligibilityProofService.already_voted?(nullifier, election.id.to_s)).to be false
    end
  end

  # ─────────────────────────────────────────────────────────
  # 7. Critical Guard: Domestic vs Diaspora Ballot Separation
  # ─────────────────────────────────────────────────────────
  describe "ballot separation guard" do
    it "domestic voter NEVER gets Dyaspora constituency" do
      citizen = create(:user, :domestic, dob: 25.years.ago)
      create(:identity_submission, :approved, user: citizen, country_of_residence: "HT")

      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record.constituency_name).not_to eq("Dyaspora")
      expect(record.channel).to eq("domestic")
    end

    it "diaspora voter ALWAYS gets Dyaspora constituency" do
      citizen = create(:user, :diaspora, dob: 25.years.ago)
      create(:identity_submission, :approved, user: citizen, country_of_residence: "FR", host_country_id_type: "passport")

      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record.constituency_name).to eq("Dyaspora")
      expect(record.channel).to eq("diaspora")
    end

    it "domestic voter gets a local department code, not a country code" do
      citizen = create(:user, :domestic, dob: 25.years.ago)
      create(:identity_submission, :approved, user: citizen, country_of_residence: "HT")

      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      # Should be a Haiti department slug, not an ISO country code
      expect(record.department_code).to eq("ouest")
      expect(%w[US FR CA]).not_to include(record.department_code)
    end

    it "diaspora voter gets country code, not a Haiti department" do
      citizen = create(:user, :diaspora, dob: 25.years.ago)
      create(:identity_submission, :approved, user: citizen, country_of_residence: "US", host_country_id_type: "passport")

      record = VoterEligibilityRecord.register_voter!(election: election, user: citizen)

      expect(record.department_code).to eq("US")
      expect(%w[ouest nord sud artibonite]).not_to include(record.department_code)
    end
  end
end
