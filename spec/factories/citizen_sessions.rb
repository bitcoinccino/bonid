FactoryBot.define do
  factory :citizen_session do
    association :user, factory: [ :user, :citizen ]
    association :citizen_profile, factory: :citizen_profile

    otp_digest { BCrypt::Password.create("123456") }
    expires_at { 10.minutes.from_now }
    used_at { nil }
    device_fingerprint { "127.0.0.1-Chrome" }

    trait :expired do
      expires_at { 10.minutes.ago }
    end

    trait :used do
      used_at { Time.current }
    end
  end
end
