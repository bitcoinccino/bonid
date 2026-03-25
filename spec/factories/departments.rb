FactoryBot.define do
  factory :department do
    sequence(:id) { |n| n }
    name { "Ouest" }
    postal_code_prefix { "HT61" }
  end
end
