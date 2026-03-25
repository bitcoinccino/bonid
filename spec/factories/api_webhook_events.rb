FactoryBot.define do
  factory :api_webhook_event do
    partner { nil }
    event_type { "MyString" }
    bonid { "MyString" }
    payload { "" }
  end
end
