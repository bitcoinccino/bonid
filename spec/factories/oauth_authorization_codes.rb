FactoryBot.define do
  factory :oauth_authorization_code do
    code_digest { "MyString" }
    expires_at { "2025-10-27 08:16:40" }
    used_at { "2025-10-27 08:16:40" }
    oauth_application { nil }
    citizen { nil }
    redirect_uri { "MyText" }
  end
end
