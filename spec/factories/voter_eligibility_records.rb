# frozen_string_literal: true

FactoryBot.define do
  factory :voter_eligibility_record do
    association :bonvote_election
    association :user
    sequence(:bonid) { |n| "VP-1990-M-OU-P#{1000 + n}-#{SecureRandom.hex(2).upcase}" }
    department_code { "OU" }
    status { "eligible" }
    constituency_name { "Ouest" }
    channel { "domestic" }
    has_voted { false }

    trait :ineligible do
      status { "ineligible" }
      constituency_name { nil }
      ineligibility_reason { "underage" }
    end

    trait :diaspora do
      channel { "diaspora" }
      constituency_name { "Dyaspora" }
    end

    trait :voted do
      has_voted { true }
      voted_at { Time.current }
    end
  end
end
