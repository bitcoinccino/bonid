# spec/factories/partners.rb
FactoryBot.define do
  factory :partner do
    sequence(:name) { |n| "BonID Test Partner #{n}" }
    sequence(:slug) { |n| "bonid-test-partner-#{n}-#{SecureRandom.hex(4)}" } # ✅ force uniqueness
    contact_person { "Jane Doe" }
    email { "partner@example.com" }
    sector { "banking" }
    verified_at { nil } # default unverified
    use_cases { [ "identity_verification" ] }
    website { "https://partner.example.com" }
    street_address { "Rue Chavannes 23" }
    postal_code { "HT6120" }
    commune { "Delmas" }
    department { "Ouest" }
    country { "Haiti" }
    latitude { 18.5425 }
    longitude { -72.3386 }
    description { "Test partner for BonID API integration" }
    phone_number { "+50937000000" }
    active { true }

    # ✅ Allows overriding the key in individual tests
    transient do
      raw_api_key { "valid_api_key_123" }
    end

    # ✅ Generate a valid bcrypt digest
    api_key_digest { |evaluator| BCrypt::Password.create(evaluator.raw_api_key) }

    # ✅ Expose raw_api_key to the instance (for test headers)
    after(:build) do |partner, evaluator|
      partner.define_singleton_method(:raw_api_key) { evaluator.raw_api_key }
      partner.define_singleton_method(:api_key_plain) { evaluator.raw_api_key }
    end

    # Optional associations
    association :admin_user, factory: :admin_user, strategy: :build

    # ✅ Trait for verified/active partner
    trait :verified do
      verified_at { Time.current }
      active { true }
    end

    # Trait for partner with credits (for API tests)
    trait :with_credits do
      credit_balance { 10_000 }
    end

    # NEW: Trait for full partner with address
    trait :with_address do
      after(:create) { |partner| partner.build_address(department: create(:department), commune: create(:commune)); partner.address.save! }
    end
  end
end
