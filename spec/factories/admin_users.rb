# spec/factories/admin_users.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :admin_user do
    sequence(:email) { |n| "admin#{n}@bonid.ht" }
    password { "securePassword123" }
    password_confirmation { "securePassword123" }
  end
end
