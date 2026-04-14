# frozen_string_literal: true

# Stores a SHA-256 hash of the Rekognition face_id from the approved
# IdentitySubmission. This anchors voter key derivation to the actual
# biometric enrolled during BonID verification — even if someone steals
# a BonID session, they can't produce the correct nullifier without
# the original indexed face.
class AddBiometricFingerprintToVoterEligibilityRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :voter_eligibility_records, :biometric_fingerprint, :string
  end
end
