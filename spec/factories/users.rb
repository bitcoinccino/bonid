# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "citizen#{n}@bonid.ht" }
    sequence(:bonid) { |n| "MO-1968-M-OUEST-P-#{1000 + n}" }

    first_name { "Jean" }
    last_name  { "Louis" }
    phone      { "+509#{rand(10000000..99999999)}" }

    password { "SecurePass123!" }
    password_confirmation { "SecurePass123!" }
    confirmed_at { Time.current }

    dob { "1990-01-01" }
    sex { :male }
    marital_status { :single }
    nationality { "Haitian" }
    active { true }

    after(:create) do |user|
      user.add_role(:citizen) if user.respond_to?(:add_role)
    end

    # ===== Address trait =====
    trait :with_address do
      after(:create) do |user|
        department = Department.first || create(:department, id: 1, name: "Ouest", postal_code_prefix: "HT61")
        arrondissement = Arrondissement.first || create(:arrondissement, id: 1, name: "Port-au-Prince", department: department)
        commune = Commune.first || create(:commune, id: 1, name: "Port-au-Prince", arrondissement: arrondissement, department_id: department.id, postal_code: "HT6110")
        communal_section = CommunalSection.first || create(:communal_section, id: 1, name: "1re Section Test", commune: commune, postal_code: "HT6000")

        address = create(:address,
                         addressable: user,
                         street_address: "123 Rue Test",
                         locality: "Port-au-Prince",
                         postal_code: "HT6110",
                         commune_id: commune.id,
                         department_id: department.id,
                         communal_section: communal_section,
                         country: "Haiti")

        user.update!(address: address)
      end
    end

    # ===== Verified identity trait =====
    trait :verified do
      after(:create) do |user|
        create(:identity_submission,
               user: user,
               status: :approved,
               id_type: :cin,
               verified_at: Time.current,
               expires_at: 1.year.from_now,
               bonid: user.bonid)
      end
    end

    # ===== Pending identity trait =====
    trait :pending_identity do
      after(:create) do |user|
        create(:identity_submission, :pending, user: user)
      end
    end
  end
end
