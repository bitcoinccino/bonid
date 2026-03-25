FactoryBot.define do
  factory :partner_access_log do
    partner { nil }
    admin_user { nil }
    action { "MyString" }
    reason { "MyString" }
    metadata { "" }
  end
end
