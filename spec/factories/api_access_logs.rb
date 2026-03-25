FactoryBot.define do
  factory :api_access_log do
    association :partner
    association :user

    endpoint    { "/api/v1/verify_identity" }
    ip_address  { "127.0.0.1" }
    success     { true }
    metadata    { { bonid: "MO-1968-M-OUEST-P-6790", status: 200, message: "verified" } }

    created_at  { Time.current }
    updated_at  { Time.current }
  end
end
