# frozen_string_literal: true

FactoryBot.define do
  factory :election_candidate do
    association :election, factory: :bonvote_election
    association :election_constituency
    full_name { "Jean-Pierre Alexandre" }
    position { "president" }
    status { "active" }
    registration_status { "submitted" }
    submitted_at { Time.current }
    candidacy_type { "independent" }

    trait :approved do
      registration_status { "approved" }
    end

    trait :rejected do
      registration_status { "rejected" }
      rejection_reason { "Dokiman pa konplè" }
    end

    trait :party do
      candidacy_type { "party" }
      party_name { "Pati Ayisyen Tèt Kale" }
      party_acronym { "PHTK" }
    end

    trait :senator do
      position { "senator" }
      association :election_constituency, factory: [ :election_constituency, :senator ]
    end

    trait :deputy do
      position { "deputy" }
      association :election_constituency, factory: [ :election_constituency, :deputy ]
    end
  end
end
