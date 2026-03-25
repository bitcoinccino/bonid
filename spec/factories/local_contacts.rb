FactoryBot.define do
  factory :local_contact do
    name { "MyString" }
    phone { "MyString" }
    email { "MyString" }
    relationship { "MyString" }
    verified { false }
    bonid { "MyString" }
    user { nil }
  end
end
