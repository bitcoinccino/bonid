FactoryBot.define do
  factory :communal_section do
    sequence(:id) { |n| n }
    name { "1re Section Test" }
    association :commune
    postal_code { "HT6000" }
  end
end
