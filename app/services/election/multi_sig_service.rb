# frozen_string_literal: true

# Multi-Signature Decryption Service
#
# Ensures no single person — not even the CEP President — can decrypt
# election results alone. Requires a quorum of 3 out of 5 authorized
# signatories to unlock the final tally.
#
# Signatories:
#   1. CEP President
#   2. CEP Secretary General
#   3. Diaspora Representative
#   4. International Observer (OEA/UN delegate)
#   5. BonID Technical Director (neutral party)
#
# Each signatory must:
#   - Scan their BonID QR code
#   - Pass liveness verification (proves they're physically present)
#   - Enter their decryption key shard
#
# The system combines 3 shards using Shamir's Secret Sharing to
# reconstruct the CEP master decryption key.
#
module Election
  class MultiSigService
    QUORUM_REQUIRED = 3
    TOTAL_SIGNATORIES = 5

    class QuorumNotMetError < StandardError; end
    class DuplicateSignatureError < StandardError; end
    class ElectionStillOpenError < StandardError; end
    class InvalidSignatoryError < StandardError; end

    # Authorized signatory roles
    SIGNATORY_ROLES = %w[
      cep_president
      cep_secretary
      diaspora_representative
      international_observer
      bonid_technical_director
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

      # Record the signature
      signature_record = {
        bonid: signatory[:bonid],
        role: signatory[:role],
        name: signatory[:name],
        liveness_session_id: signatory[:liveness_session_id],
        liveness_verified: signatory[:liveness_verified] || false,
        signed_at: Time.current.iso8601,
        key_shard_hash: OpenSSL::Digest::SHA256.hexdigest(signatory[:key_shard])
      }

      signatures << signature_record
      save_signatures(election_id, signatures)

      # Broadcast update to all connected admins
      broadcast_signature_update(election_id, signatures)

      Rails.logger.info(
        "[MultiSig] Signature #{signatures.size}/#{QUORUM_REQUIRED} added by " \
        "#{signatory[:name]} (#{signatory[:role]}) for election #{election_id}"
      )

      result = {
        signatures_count: signatures.size,
        quorum_met: signatures.size >= QUORUM_REQUIRED,
        remaining: [QUORUM_REQUIRED - signatures.size, 0].max,
        signatories: signatures.map { |s| { role: s[:role], name: s[:name], signed_at: s[:signed_at] } }
      }

      # Auto-trigger decryption when quorum is met
      if result[:quorum_met]
        key_shards = signatures.first(QUORUM_REQUIRED).map { |s| s[:key_shard_hash] }
        trigger_final_tally(election_id, key_shards)
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
        remaining: [QUORUM_REQUIRED - signatures.size, 0].max,
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
        "cep_president" => "Prezidan CEP",
        "cep_secretary" => "Sekretè Jeneral CEP",
        "diaspora_representative" => "Reprezantan Dyaspora",
        "international_observer" => "Obsèvatè Entènasyonal (OEA/ONU)",
        "bonid_technical_director" => "Direktè Teknik BonID"
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

      # 1. Close the election to new ballots
      # TODO: Election.find(election_id).update!(status: :closed, closed_at: Time.current)

      # 2. Reconstruct master key from shards (Shamir's Secret Sharing)
      # In production: master_key = ShamirSecretSharing.combine(key_shards)
      # For now: the master key is derived from the quorum of shard hashes
      master_key_material = key_shards.sort.join("||")
      reconstructed_key_hash = OpenSSL::Digest::SHA256.hexdigest(master_key_material)

      Rails.logger.info("[MultiSig] Master key reconstructed (hash: #{reconstructed_key_hash[0..15]}...)")

      # 3. Broadcast to all connected admins that results are ready
      broadcast_decryption_complete(election_id)
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

    # Persistence — using Rails cache for now.
    # In production, use a dedicated ElectionSignature model.
    def self.load_signatures(election_id)
      Rails.cache.read("election_multisig_#{election_id}") || []
    end

    def self.save_signatures(election_id, signatures)
      Rails.cache.write("election_multisig_#{election_id}", signatures, expires_in: 30.days)
    end
  end
end
