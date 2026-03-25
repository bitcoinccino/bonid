FactoryBot.define do
  factory :citizen_profile do
    association :user, factory: [ :user, :citizen ]
  end
end
