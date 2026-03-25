FactoryBot.define do
  factory :commune do
    sequence(:id) { |n| n }
    name { "Port-au-Prince" }
    association :arrondissement
    department_id { arrondissement.department.id }
    postal_code { "HT6110" }
  end
end
