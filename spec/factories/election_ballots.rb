# frozen_string_literal: true

FactoryBot.define do
  factory :election_ballot do
    association :election, factory: [ :bonvote_election, :open ]
    sequence(:nullifier) { |n| SecureRandom.hex(16) }
    position { "president" }
    encrypted_choice { { encrypted_choice: SecureRandom.hex(32), encrypted_key: SecureRandom.hex(16), iv: SecureRandom.hex(8), auth_tag: SecureRandom.hex(8) }.to_json }
    zkp_commitment { SecureRandom.hex(32) }
    zkp_proof { { challenge: SecureRandom.hex(16), response: SecureRandom.hex(16), public_commitment: SecureRandom.hex(16) } }
    sequence(:ballot_hash) { |n| Digest::SHA256.hexdigest("ballot-#{n}-#{SecureRandom.hex(8)}") }
    sequence(:receipt_id) { |n| "RCP-#{SecureRandom.hex(6).upcase}" }
    channel { "remote" }
    cast_at { Time.current }

    trait :consulate do
      channel { "consulate" }
      consulate_id { "HTI-MIA" }
    end

    trait :in_person do
      channel { "in_person" }
    end

    trait :flagged do
      location_flagged { true }
      ip_country { "US" }
      department_code { "OU" }
    end
  end
end
