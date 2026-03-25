# spec/factories/consent_grants.rb
FactoryBot.define do
  factory :consent_grant do
    association :citizen, factory: :user
    association :partner

    grant_token       { SecureRandom.hex(16) }
    requested_scopes  { %w[identity bank] }
    status            { :pending }
    audit_log         { {} }
    granted_at        { nil }
    expires_at        { nil }

    trait :approved do
      status { :approved }
      granted_at { Time.current }
      expires_at { 3.months.from_now }
    end

    trait :revoked do
      status { :revoked }
      revoked_at { Time.current }
    end
  end
end
