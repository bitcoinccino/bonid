FactoryBot.define do
  factory :arrondissement do
    sequence(:id) { |n| n }
    name { "Port-au-Prince" }
    association :department
    code { "AR-001" }
  end
end
