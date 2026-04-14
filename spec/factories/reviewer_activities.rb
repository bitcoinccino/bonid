# frozen_string_literal: true

FactoryBot.define do
  factory :reviewer_activity do
    association :user
    action { "view_submission" }
    ip_address { "127.0.0.1" }
    metadata { {} }
  end
end
