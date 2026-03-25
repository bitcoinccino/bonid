# frozen_string_literal: true

FactoryBot.define do
  factory :incident_report do
    officer
    partner_id { officer.partner_id }
    crime_type { "Theft" }
    description { Faker::Lorem.paragraph(sentence_count: 3) }
    occurred_at { 1.day.ago }
    uuid { SecureRandom.uuid }
    status { "draft" }

    # --- Crime type traits ---
    trait :kidnapping do
      crime_type { "Kidnapping" }
    end

    trait :police_brutality do
      crime_type { "Police Brutality" }
    end

    trait :child_abduction do
      crime_type { "Child Abduction" }
    end

    trait :homicide do
      crime_type { "Homicide" }
    end

    trait :drug_trafficking do
      crime_type { "Drug Trafficking" }
    end

    trait :financial_fraud do
      crime_type { "Financial Fraud" }
    end

    trait :traffic_violation do
      crime_type { "Traffic Violation" }
    end

    trait :treason do
      crime_type { "Treason" }
    end

    # --- Status traits ---
    trait :submitted do
      status { "submitted" }
      submitted_at { Time.current }
      signed_by_badge_id { officer.badge_id }
    end
  end
end
