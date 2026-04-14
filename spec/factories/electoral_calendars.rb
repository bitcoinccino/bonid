# frozen_string_literal: true

FactoryBot.define do
  factory :electoral_calendar do
    association :bonvote_election
    phase { "candidate_registration" }
    name { "Depo Kandida" }
    start_date { Date.current - 5.days }
    end_date { Date.current + 25.days }
    public_visible { true }
    responsible_body { "cep" }

    trait :active do
      start_date { Date.current - 5.days }
      end_date { Date.current + 5.days }
    end

    trait :past do
      start_date { Date.current - 30.days }
      end_date { Date.current - 10.days }
    end

    trait :upcoming do
      start_date { Date.current + 10.days }
      end_date { Date.current + 30.days }
    end

    trait :voting_day do
      phase { "voting_day" }
      name { "Jou Vòt (1ye tou)" }
    end
  end
end
