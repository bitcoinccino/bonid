# frozen_string_literal: true

FactoryBot.define do
  factory :identity_submission do
    association :user
    association :partner

    id_type { :cin }
    submission_type { :initial }
    status { :pending }

    bonid { user.bonid }
    verification_token { SecureRandom.hex(16) }

    verified_at { nil }
    expires_at  { nil }

    public_qr_png_base64 { "data:image/png;base64,fake_qr_base64" }
    secure_qr_png_base64 { "data:image/png;base64,fake_secure_qr_base64" }

    trait :pending do
      status { :pending }
      verified_at { nil }
      expires_at { nil }
    end

    trait :approved do
      status { :approved }
      verified_at { Time.current }
      expires_at { 1.year.from_now }
    end

    trait :rejected do
      status { :rejected }
      rejection_reason { "blurry_id" }
    end

    trait :reissue do
      submission_type { :reissue }
      reason { "Lost ID" }
      status { :pending }
    end
  end
end
