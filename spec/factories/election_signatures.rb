# frozen_string_literal: true

FactoryBot.define do
  factory :election_signature do
    association :election, factory: [ :bonvote_election, :closed ]
    sequence(:bonid) { |n| "VP-1970-M-OU-P#{1000 + n}-#{SecureRandom.hex(2).upcase}" }
    sequence(:role) { |n| ElectionSignature::ROLES[n % ElectionSignature::ROLES.size] }
    signatory_name { "Manm CEP" }
    signed_at { Time.current }
    liveness_verified { true }
    key_shard_hash { Digest::SHA256.hexdigest(SecureRandom.hex(16)) }
  end
end
