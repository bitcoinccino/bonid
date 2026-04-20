# frozen_string_literal: true

module Election
  # Single source of truth for BonVote signing keys per election.
  #
  # Today's flow:
  #   - Source: encrypted credentials at
  #       election.bonvote_signing_keys.<election_id>.{ private:, public: }
  #     (base64 of raw 32-byte Ed25519 seed / 32-byte public key)
  #   - On read, the public half is mirrored into
  #       bonvote_elections.bonvote_public_key (string column)
  #     so verifiers can pull it from the DB / API without touching
  #     credentials.
  #   - Rotation: when a key is replaced, the previous {key_id, public_key}
  #     is appended to metadata["bonvote_archived_keys"] so receipts signed
  #     under the old key remain verifiable forever.
  #
  # `key_id` is a stable, human-traceable identifier:
  #   "bonvote-election-<id>-<YYYY-MM>"
  # It binds a particular signature to a particular key version. Verifiers
  # use `key_id` from the receipt to look up the right public key (current
  # if matching, archived otherwise).
  class BonvoteKeyRegistry
    Key = Struct.new(:key_id, :public_key_b64, :algorithm, :rotated_at, keyword_init: true) do
      def to_h
        {
          key_id:         key_id,
          algorithm:      algorithm,
          public_key_b64: public_key_b64,
          rotated_at:     rotated_at&.iso8601
        }.compact
      end
    end

    ALGORITHM = "Ed25519"

    def self.current(election)
      new(election).current
    end

    def self.find_by_key_id(election, key_id)
      new(election).find_by_key_id(key_id)
    end

    def self.all(election)
      new(election).all
    end

    # Mirrors the credential public key into the DB column + assigns a
    # key_id if missing. Idempotent: safe to call repeatedly. Returns the
    # current Key struct, or nil when no credential exists.
    def self.sync!(election)
      new(election).sync!
    end

    def initialize(election)
      @election = election
    end

    def current
      pub = @election.bonvote_public_key.presence
      return nil if pub.blank?

      Key.new(
        key_id:         @election.bonvote_key_id.presence || default_key_id,
        public_key_b64: pub,
        algorithm:      ALGORITHM,
        rotated_at:     nil
      )
    end

    def all
      [ current, *archived_keys ].compact
    end

    def find_by_key_id(key_id)
      all.find { |k| k.key_id == key_id }
    end

    def sync!
      cred_pub = Rails.application.credentials.dig(
        :election, :bonvote_signing_keys, @election.id.to_s.to_sym, :public
      )
      return nil if cred_pub.blank?

      attrs = {}
      attrs[:bonvote_public_key] = cred_pub if @election.bonvote_public_key != cred_pub
      attrs[:bonvote_key_id]     = default_key_id if @election.bonvote_key_id.blank?
      @election.update!(attrs) if attrs.any?

      current
    end

    private

    def archived_keys
      Array(@election.metadata&.dig("bonvote_archived_keys")).map do |entry|
        Key.new(
          key_id:         entry["key_id"],
          public_key_b64: entry["public_key_b64"],
          algorithm:      entry["algorithm"] || ALGORITHM,
          rotated_at:     entry["rotated_at"] && Time.parse(entry["rotated_at"])
        )
      end
    rescue ArgumentError
      []
    end

    def default_key_id
      "bonvote-election-#{@election.id}-#{(@election.opened_at || @election.created_at || Time.current).strftime('%Y-%m')}"
    end
  end
end
