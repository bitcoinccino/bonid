# frozen_string_literal: true

# Public receipt verifier — no login required.
#
# Lets anyone (citizen, family member, journalist, observer) confirm that a
# BonVote receipt was actually issued by BonID by re-checking the Ed25519
# signature against the election's published public key.
#
# Three ways in:
#   1. GET  /election/verify-receipt?d=<base64url(payload_json)>
#      QR code on the receipt encodes this URL — phone camera scan opens
#      the page with payload pre-filled.
#   2. POST /election/verify-receipt  with `voter_reference` form field
#      Citizen enters their BVT-2026-XXXX-YYYY number — server looks up
#      the record and reconstructs the payload + signature.
#   3. POST /election/verify-receipt  with `payload_json` form field
#      Power-user / observer paste fallback for raw payloads.
#
# The check is purely cryptographic: we recompute the canonical signing
# payload (everything except the signature itself), look up the right
# public key by `kid` from BonvoteKeyRegistry, and ask
# BonvoteSigningService to verify. No DB write, no PII surfaced beyond
# what's already in the QR.
module Election
  class VerifyReceiptController < ApplicationController
    skip_before_action :authenticate_user!,        raise: false
    skip_before_action :authenticate_citizen!,     raise: false
    skip_before_action :verify_authenticity_token, raise: false
    protect_from_forgery with: :null_session

    # GET — render the form (and auto-verify if `d=` is present).
    def show
      @result = decode_and_verify(params[:d]) if params[:d].present?
      render layout: false
    end

    # POST — voter-reference lookup OR raw JSON paste fallback.
    def verify
      ref = params[:voter_reference].to_s.strip
      raw = params[:payload_json].to_s.strip

      @result = if ref.present?
                  verify_by_reference(ref)
                elsif raw.present?
                  decode_and_verify_raw(raw)
                else
                  { ok: false, error: "Antre nimewo votè w oswa peyad la." }
                end

      render :show, layout: false
    end

    private

    # Citizen-friendly path: look up the record by voter_reference, rebuild
    # the canonical payload from current DB state, and verify the stored
    # signature against the published public key. Citizen never has to
    # touch JSON.
    def verify_by_reference(ref)
      # Normalize: uppercase + strip spaces. References are issued upper-
      # case (BVT-2026-XXXX-YYYY) but citizens may type them in any case.
      record = VoterEligibilityRecord.find_by_voter_reference(ref)
      return { ok: false, error: "Pa gen okenn resi ki koresponn ak nimewo sa a." } if record.nil?

      if record.bonvote_signature.blank?
        return { ok: false, error: "Resi sa a poko siyen." }
      end

      payload = record.receipt_qr_payload
      verify_payload(payload)
    end

    # Decodes a base64url-encoded JSON payload and verifies it.
    def decode_and_verify(encoded)
      json = Base64.urlsafe_decode64(encoded.to_s)
      decode_and_verify_raw(json)
    rescue ArgumentError
      { ok: false, error: "Kòd QR la pa valid (base64 malfòme)." }
    end

    # Verifies a raw JSON payload string. Returns a result hash the view
    # can render directly — no exceptions leak out.
    def decode_and_verify_raw(json)
      payload = JSON.parse(json)
      payload = payload.transform_keys(&:to_sym) if payload.is_a?(Hash)
    rescue JSON::ParserError
      return { ok: false, error: "Peyad la pa JSON valid." }
    else
      verify_payload(payload)
    end

    def verify_payload(payload)
      return { ok: false, error: "Peyad la pa gen fòma rekonèt." } unless payload.is_a?(Hash)

      election_id = payload[:e] || payload["e"]
      signature   = payload[:s] || payload["s"]
      key_id      = payload[:kid] || payload["kid"]

      return { ok: false, error: "Pa gen siyati nan resi a — resi sa a pa siyen." } if signature.blank?
      return { ok: false, error: "Pa gen referans eleksyon nan resi a." } if election_id.blank?

      election = BonvoteElection.find_by(id: election_id)
      return { ok: false, error: "Eleksyon ##{election_id} pa egziste." } if election.nil?

      ::Election::BonvoteKeyRegistry.sync!(election)

      # Strip the signature itself before verifying — that's the same
      # canonical payload that was signed at receipt-stamp time.
      signing_payload = payload.reject { |k, _| k.to_s == "s" }

      ok = ::Election::BonvoteSigningService.verify(
        election:      election,
        payload:       signing_payload,
        signature_b64: signature,
        key_id:        key_id
      )

      key = ::Election::BonvoteKeyRegistry.find_by_key_id(election, key_id) if key_id.present?
      key ||= ::Election::BonvoteKeyRegistry.current(election)

      {
        ok:           ok,
        payload:      signing_payload,
        signature:    signature,
        key_id:       key_id,
        election:     election,
        public_key:   key&.public_key_b64,
        fingerprint:  key && Digest::SHA256.hexdigest(Base64.decode64(key.public_key_b64)),
        verified_at:  Time.current
      }
    end
  end
end
