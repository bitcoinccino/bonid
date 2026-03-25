FactoryBot.define do
  factory :partner_audit_log do
    partner { nil }
    admin_user { nil }
    event { "MyString" }
    details { "MyText" }
    metadata { "" }
    created_at { "2025-11-05 21:54:49" }
  end
end
