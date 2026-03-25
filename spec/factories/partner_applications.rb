FactoryBot.define do
  factory :partner_application do
    organization_name { "BonID Test Organization" }
    contact_person    { "Jane Doe" }
    email             { "partner@example.com" }
    phone_number      { "+50937000000" }
    website           { "https://partner.example.com" }
    status            { "approved" }
  end
end
