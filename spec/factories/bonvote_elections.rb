# frozen_string_literal: true

FactoryBot.define do
  factory :bonvote_election do
    sequence(:title) { |n| "Eleksyon Jeneral #{2026 + n}" }
    election_type { "general" }
    round { 1 }
    status { "draft" }
    election_date { Date.new(2026, 8, 30) }

    trait :open do
      status { "open" }
      opened_at { Time.current }
    end

    trait :closed do
      status { "closed" }
      opened_at { 1.day.ago }
      closed_at { Time.current }
    end

    trait :certified do
      status { "certified" }
      opened_at { 3.days.ago }
      closed_at { 2.days.ago }
      certified_at { Time.current }
    end

    trait :presidential do
      election_type { "presidential" }
    end

    trait :round_two do
      round { 2 }
      association :parent_election, factory: [ :bonvote_election, :closed ]
    end

    trait :with_constituency do
      after(:create) do |election|
        create(:election_constituency, election: election)
      end
    end
  end
end
