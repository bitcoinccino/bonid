FactoryBot.define do
  factory :partner_api_log do
    partner { nil }
    endpoint { "MyString" }
    request_method { "MyString" }
    status_code { 1 }
    status { 1 }
    response_time_ms { 1.5 }
    ip_address { "MyString" }
    user_agent { "MyText" }
    request_payload { "MyText" }
    response_body { "MyText" }
    requested_at { "2025-10-29 18:10:59" }
  end
end
