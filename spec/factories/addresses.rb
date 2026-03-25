# spec/factories/addresses.rb
FactoryBot.define do
  factory :address do
    addressable { nil }
    street_address { "123 Rue Test" }
    locality { "Port-au-Prince" }
    postal_code { "HT6110" }
    commune_id { 1 }
    department_id { 1 }
    communal_section_id { 1 }
    country { "Haiti" }
  end
end
