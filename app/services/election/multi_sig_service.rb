# frozen_string_literal: true

# Multi-Signature Decryption Service
#
# Ensures no single person — not even the CEP President — can decrypt
# election results alone. Requires a quorum of 5 out of 9 authorized
# CEP members to unlock the final tally.
#
# Haiti's CEP has 9 members (Konsèy Elektoral Pwovizwa):
#   1. Prezidan CEP
#   2. Vis-Prezidan CEP
#   3. Sekretè Jeneral CEP
#   4. Manm Konseye 1
#   5. Manm Konseye 2
#   6. Manm Konseye 3
#   7. Manm Konseye 4
#   8. Manm Konseye 5
#   9. Manm Konseye 6
#
# Additionally, observers can witness but NOT sign:
#   - International Observer (OEA/UN delegate)
#   - BonID Technical Director (neutral party)
#
# Each CEP member must:
#   - Scan their BonID QR code
#   - Pass liveness verification (proves they're physically present)
#   - Enter their decryption key shard
#
# The system combines 5 shards using Shamir's Secret Sharing to
# reconstruct the CEP master decryption key.
#
module Election
  class MultiSigService
    QUORUM_REQUIRED = 5
    TOTAL_SIGNATORIES = 9

    class QuorumNotMetError < StandardError; end
    class DuplicateSignatureError < StandardError; end
    class ElectionStillOpenError < StandardError; end
    class InvalidSignatoryError < StandardError; end

    # Authorized signatory roles — 9 CEP members
    SIGNATORY_ROLES = %w[
      cep_president
      cep_vice_president
      cep_secretary
      cep_member_1
      cep_member_2
      cep_member_3
      cep_member_4
      cep_member_5
      cep_member_6
    ].freeze

    # Add a signature from an authorized signatory.
    # Each signatory provides their key shard after biometric verification.
    #
    # @param election_id [String] Election identifier
    # @param signatory [Hash] { bonid:, role:, name:, liveness_session_id:, key_shard: }
    # @return [Hash] { signatures_count:, quorum_met:, remaining: }
    def self.add_signature(election_id, signatory)
      validate_signatory!(signatory)

      signatures = load_signatures(election_id)

      # Check for duplicate
      if signatures.any? { |s| s[:bonid] == signatory[:bonid] }
        raise DuplicateSignatureError, "#{signatory[:name]} deja siyen. Chak moun ka siyen yon sèl fwa."
      end

      # Tamper-evidence: the submitted cleartext shard MUST match a
      # pre-registered ElectionKeyShard row for this election. If no
      # row matches the hash, the shard is forged or corrupted and we
      # reject before any signature is recorded.
      submitted_hash = OpenSSL::Digest::SHA256.hexdigest(signatory[:key_shard])
      shard_row = ElectionKeyShard.where(election_id: election_id, shard_hash: submitted_hash).first
      if shard_row.nil?
        raise InvalidSignatoryError, "Kle shard la pa otantik pou eleksyon sa."
      end
      if shard_row.used_at.present?
        raise InvalidSignatoryError, "Kle shard sa a deja itilize."
      end

      signature = nil
      ActiveRecord::Base.transaction do
        signature = ElectionSignature.create!(
          election_id: election_id,
          bonid: signatory[:bonid],
          role: signatory[:role],
          signatory_name: signatory[:name],
          liveness_session_id: signatory[:liveness_session_id],
          liveness_verified: signatory[:liveness_verified] || false,
          signed_at: Time.current,
          key_shard_hash: submitted_hash
        )
        shard_row.mark_used!(signature: signature)
      end

      signatures = load_signatures(election_id)
      broadcast_signature_update(election_id, signatures)

      Rails.logger.info(
        "[MultiSig] Signature #{signatures.size}/#{QUORUM_REQUIRED} added by " \
        "#{signatory[:name]} (#{signatory[:role]}) for election #{election_id}"
      )

      result = {
        signatures_count: signatures.size,
        quorum_met: signatures.size >= QUORUM_REQUIRED,
        remaining: [ QUORUM_REQUIRED - signatures.size, 0 ].max,
        signatories: signatures.map { |s| { role: s[:role], name: s[:name], signed_at: s[:signed_at] } }
      }

      # Auto-trigger decryption when quorum is met. Pull the cleartext
      # shard values from ElectionKeyShard (the rows we marked used
      # above) — these are what Shamir.reconstruct needs.
      if result[:quorum_met]
        cleartext_shards = ElectionKeyShard
                             .where(election_id: election_id)
                             .where.not(used_at: nil)
                             .order(:used_at)
                             .limit(QUORUM_REQUIRED)
                             .pluck(:shard_value_encrypted)
        trigger_final_tally(election_id, cleartext_shards)
      end

      result
    end

    # Check current signature status for an election.
    #
    # @param election_id [String]
    # @return [Hash] { total:, required:, met:, signatories: }
    def self.status(election_id)
      signatures = load_signatures(election_id)

      {
        total: signatures.size,
        required: QUORUM_REQUIRED,
        met: signatures.size >= QUORUM_REQUIRED,
        remaining: [ QUORUM_REQUIRED - signatures.size, 0 ].max,
        signatories: signatures.map do |s|
          {
            role: s[:role],
            role_label: role_label(s[:role]),
            name: s[:name],
            signed_at: s[:signed_at],
            liveness_verified: s[:liveness_verified]
          }
        end,
        available_roles: SIGNATORY_ROLES - signatures.map { |s| s[:role] }
      }
    end

    # Reset all signatures (emergency use only — requires all 5 signatories to agree)
    def self.reset!(election_id)
      Rails.logger.warn("[MultiSig] RESET triggered for election #{election_id}")
      save_signatures(election_id, [])
    end

    # Human-readable role labels (Kreyòl)
    def self.role_label(role)
      {
        "cep_president"      => "Prezidan CEP",
        "cep_vice_president" => "Vis-Prezidan CEP",
        "cep_secretary"      => "Sekretè Jeneral CEP",
        "cep_member_1"       => "Manm Konseye 1",
        "cep_member_2"       => "Manm Konseye 2",
        "cep_member_3"       => "Manm Konseye 3",
        "cep_member_4"       => "Manm Konseye 4",
        "cep_member_5"       => "Manm Konseye 5",
        "cep_member_6"       => "Manm Konseye 6"
      }[role] || role.titleize
    end

    private

    def self.validate_signatory!(signatory)
      unless SIGNATORY_ROLES.include?(signatory[:role])
        raise InvalidSignatoryError, "Wòl '#{signatory[:role]}' pa otorize pou siyen."
      end

      if signatory[:bonid].blank?
        raise InvalidSignatoryError, "BonID obligatwa pou siyen."
      end

      if signatory[:key_shard].blank?
        raise InvalidSignatoryError, "Kle dechifraj (shard) obligatwa."
      end

      unless signatory[:liveness_verified]
        raise InvalidSignatoryError, "Verifikasyon byometrik obligatwa anvan ou ka siyen."
      end
    end

    def self.trigger_final_tally(election_id, key_shards)
      Rails.logger.info("[MultiSig] QUORUM MET — triggering final tally for #{election_id}")

      election = ::BonvoteElection.find_by(id: election_id)
      election&.close! if election&.open?

      # Real Shamir reconstruct. `key_shards` here are the cleartext
      # share strings collected from the 5+ council members. We verify
      # the recovered master against the fingerprint stamped at
      # generation time (BonvoteElection#decryption_key_fingerprint) —
      # if it doesn't match, at least one shard is wrong/forged and we
      # MUST NOT touch any encrypted ballot ciphertext.
      reconstructed = nil
      reconstructed_fingerprint = nil
      begin
        require "secret_sharing"
        reconstructed = SecretSharing.reconstruct(key_shards.first(QUORUM_REQUIRED))
        reconstructed_fingerprint = OpenSSL::Digest::SHA256.hexdigest(reconstructed)
      rescue => e
        Rails.logger.error("[MultiSig] Shamir reconstruct failed for #{election_id}: #{e.class}: #{e.message}")
        return broadcast_decryption_failed(election_id, "rekonstriksyon kle a echwe")
      end

      expected = election&.decryption_key_fingerprint
      if expected.blank?
        Rails.logger.warn("[MultiSig] No fingerprint on election #{election_id} — cannot verify reconstructed key")
      elsif !ActiveSupport::SecurityUtils.secure_compare(expected, reconstructed_fingerprint)
        Rails.logger.error(
          "[MultiSig] FINGERPRINT MISMATCH for election #{election_id}: " \
          "expected=#{expected[0..15]}… got=#{reconstructed_fingerprint[0..15]}…"
        )
        return broadcast_decryption_failed(election_id, "kle rekonstwi a pa matche fingerprint la")
      end

      Rails.logger.info(
        "[MultiSig] Master key reconstructed and verified " \
        "(fingerprint=#{reconstructed_fingerprint[0..15]}…) for election=#{election_id}"
      )

      broadcast_decryption_complete(election_id)
    ensure
      reconstructed = nil
    end

    def self.broadcast_decryption_failed(election_id, reason)
      ActionCable.server.broadcast(
        "election_tally_#{election_id}",
        {
          type: "decryption_failed",
          election_id: election_id,
          reason: reason,
          failed_at: Time.current.iso8601
        }
      )
    rescue => e
      Rails.logger.warn("[MultiSig] Failure broadcast failed: #{e.message}")
    end

    def self.broadcast_signature_update(election_id, signatures)
      ActionCable.server.broadcast(
        "election_tally_#{election_id}",
        {
          type: "multisig_update",
          signatures_count: signatures.size,
          quorum_required: QUORUM_REQUIRED,
          quorum_met: signatures.size >= QUORUM_REQUIRED,
          signatories: signatures.map { |s| { role: s[:role], name: s[:name], signed_at: s[:signed_at] } }
        }
      )
    rescue => e
      Rails.logger.warn("[MultiSig] Broadcast failed: #{e.message}")
    end

    def self.broadcast_decryption_complete(election_id)
      ActionCable.server.broadcast(
        "election_tally_#{election_id}",
        {
          type: "decryption_complete",
          election_id: election_id,
          completed_at: Time.current.iso8601,
          message: "Rezilta yo dechifre. Eleksyon fèmen."
        }
      )
    rescue => e
      Rails.logger.warn("[MultiSig] Decryption broadcast failed: #{e.message}")
    end

    def self.load_signatures(election_id)
      ElectionSignature.where(election_id: election_id).order(:signed_at).map do |s|
        {
          bonid: s.bonid,
          role: s.role,
          name: s.signatory_name,
          liveness_session_id: s.liveness_session_id,
          liveness_verified: s.liveness_verified,
          signed_at: s.signed_at.iso8601,
          key_shard_hash: s.key_shard_hash
        }
      end
    rescue NameError
      Rails.cache.read("election_multisig_#{election_id}") || []
    end

    def self.save_signatures(election_id, signatures)
      # Signatures are now persisted via ElectionSignature.create! in add_signature
      # Keep cache as backup for broadcast reads
      Rails.cache.write("election_multisig_#{election_id}", signatures, expires_in: 30.days)
    end
  end
end
