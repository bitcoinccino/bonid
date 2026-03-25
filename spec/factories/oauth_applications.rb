FactoryBot.define do
  factory :oauth_application do
    name { "MyString" }
    uid { "MyString" }
    secret_digest { "MyString" }
    redirect_uri { "MyText" }
    scopes { "MyString" }
    partner { nil }
  end
end
