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
    sequence(:document_number) { |n| format("%010d", 1000000000 + n) } # Valid 10-digit NINU format
    country_of_residence { "HT" }

    # Bypass selfie attachment validation by marking liveness as reused
    metadata { { "liveness" => { "reused" => true } } }

    verified_at { nil }
    expires_at  { nil }

    public_qr_png_base64 { "data:image/png;base64,fake_qr_base64" }
    secure_qr_png_base64 { "data:image/png;base64,fake_secure_qr_base64" }

    # CIN submissions require front + back images (id_document_must_be_attached).
    after(:build) do |submission|
      next unless submission.id_type.to_s == "cin"

      png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
      %i[cin_front cin_back].each do |side|
        next if submission.public_send(side).attached?

        submission.public_send(side).attach(io: StringIO.new(png), filename: "#{side}.png", content_type: "image/png")
      end
    end

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
