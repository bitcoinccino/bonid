# frozen_string_literal: true

# AES-256-GCM encryption for the vote choice.
#
# The vote is encrypted with the CEP's public key so that:
#   - Only CEP can decrypt (not BonID, not the voter after submission)
#   - The ciphertext is authenticated (tamper-proof)
#   - The payload is compact (< 256 bytes) for low-bandwidth environments
#
module Election
  class VoteEncryptionService
    CIPHER = "aes-256-gcm"

    # Encrypt the vote choice with the CEP's election public key.
    #
    # @param choice [Integer] The ballot choice (candidate index)
    # @param cep_public_key [String] CEP's RSA public key (PEM format)
    # @param election_id [String] Election identifier (used as AAD)
    # @return [Hash] { encrypted_choice:, encrypted_key:, iv:, auth_tag: }
    def self.encrypt(choice, cep_public_key, election_id)
      # Generate ephemeral AES key
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.encrypt
      aes_key = cipher.random_key
      iv = cipher.random_iv

      # Set additional authenticated data (election context)
      cipher.auth_data = election_id

      # Encrypt the choice
      encrypted_choice = cipher.update(choice.to_s) + cipher.final
      auth_tag = cipher.auth_tag

      # Encrypt the AES key with CEP's RSA public key
      rsa = OpenSSL::PKey::RSA.new(cep_public_key)
      encrypted_key = rsa.public_encrypt(aes_key, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)

      {
        encrypted_choice: Base64.strict_encode64(encrypted_choice),
        encrypted_key: Base64.strict_encode64(encrypted_key),
        iv: Base64.strict_encode64(iv),
        auth_tag: Base64.strict_encode64(auth_tag)
      }
    end

    # Decrypt a vote (CEP-side only, using their private key).
    #
    # @param payload [Hash] The encrypted payload from encrypt()
    # @param cep_private_key [String] CEP's RSA private key (PEM format)
    # @param election_id [String] Election identifier (AAD verification)
    # @return [Integer] The decrypted vote choice
    def self.decrypt(payload, cep_private_key, election_id)
      # Decrypt the AES key with CEP's RSA private key
      rsa = OpenSSL::PKey::RSA.new(cep_private_key)
      aes_key = rsa.private_decrypt(
        Base64.strict_decode64(payload[:encrypted_key]),
        OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING
      )

      # Decrypt the vote choice
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.decrypt
      cipher.key = aes_key
      cipher.iv = Base64.strict_decode64(payload[:iv])
      cipher.auth_tag = Base64.strict_decode64(payload[:auth_tag])
      cipher.auth_data = election_id

      decrypted = cipher.update(Base64.strict_decode64(payload[:encrypted_choice])) + cipher.final
      decrypted.to_i
    end
  end
end
