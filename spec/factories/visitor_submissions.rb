FactoryBot.define do
  factory :visitor_submission do
    first_name { "MyString" }
    last_name { "MyString" }
    dob { "2025-11-12" }
    sex { "MyString" }
    passport_number { "MyString" }
    country_code { "MyString" }
    purpose_of_visit { "MyString" }
    accommodation_address { "MyString" }
    stay_duration_days { 1 }
    entry_mode { 1 }
    transport_provider { "MyString" }
    transport_details { "" }
    bonid { "MyString" }
    expires_at { "2025-11-12 12:38:57" }
    port_of_entry { "MyString" }
    transport_reference { "MyString" }
    metadata { "" }
    user { nil }
    identity_submission { nil }
  end
end
