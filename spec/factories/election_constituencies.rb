# frozen_string_literal: true

FactoryBot.define do
  factory :election_constituency do
    association :election, factory: :bonvote_election
    position { "president" }
    constituency_name { "Prezidan Repiblik d'Ayiti" }
    seats { 1 }
    electoral_system { "absolute_majority_two_round" }

    trait :senator do
      position { "senator" }
      constituency_name { "Senatè — Ouest" }
      department_code { "OU" }
      department_name { "Ouest" }
    end

    trait :deputy do
      position { "deputy" }
      constituency_name { "Depite — Delmas" }
      department_code { "OU" }
      department_name { "Ouest" }
    end
  end
end
