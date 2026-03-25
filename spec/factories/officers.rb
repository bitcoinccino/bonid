# frozen_string_literal: true

FactoryBot.define do
  factory :officer do
    sequence(:email) { |n| "officer#{n}@pnh.ht" }
    sequence(:badge_id) { |n| "PNH-#{n.to_s.rjust(6, '0')}" }
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    password { "SecurePass123!" }
    password_confirmation { "SecurePass123!" }
    rank { "Agent I" }
    unit_name { "DCPJ" }
    unit_type { "Police Scientifique (SPS)" }
    status { :active }
    role { :officer }
    approved { true }
    partner

    # --- Rank traits ---
    trait :field_rank do
      rank { "Agent I" }
    end

    trait :supervisor_rank do
      rank { "Inspecteur de Police" }
    end

    trait :strategic_rank do
      rank { "Commissaire de Police" }
    end

    # --- Unit traits (with matching unit_type for validation) ---
    trait :dcpj do
      unit_name { "DCPJ" }
      unit_type { "Police Scientifique (SPS)" }
    end

    trait :blts do
      unit_name { "BLTS" }
      unit_type { "Lutte Antidrogue" }
    end

    trait :swat do
      unit_name { "SWAT" }
      unit_type { "Entrée Tactique" }
    end

    trait :utag do
      unit_name { "UTAG" }
      unit_type { "Opérations Anti-Gang" }
    end

    trait :edupol do
      unit_name { "EDUPOL" }
      unit_type { "Éducation Communautaire" }
    end

    trait :politour do
      unit_name { "POLITOUR" }
      unit_type { "Protection Touristique" }
    end

    trait :usgpn do
      unit_name { "USGPN" }
      unit_type { "Sécurité du Palais National" }
    end

    trait :usp do
      unit_name { "USP" }
      unit_type { "Sécurité Présidentielle" }
    end

    trait :cimo do
      unit_name { "CIMO" }
      unit_type { "Contrôle des Foules" }
    end

    trait :polifront do
      unit_name { "POLIFRONT" }
      unit_type { "Sécurité Frontalière" }
    end

    trait :dcpr do
      unit_name { "DCPR" }
      unit_type { "Constat d'Accident" }
    end

    trait :udmo do
      unit_name { "UDMO" }
      unit_type { "Patrouille Urbaine" }
    end

    trait :boid do
      unit_name { "BOID" }
      unit_type { "Opérations Tactiques" }
    end

    trait :bri do
      unit_name { "BRI" }
      unit_type { "Enquête Criminelle" }
    end

    trait :polaer do
      unit_name { "POLAER" }
      unit_type { "Police Aéroportuaire" }
    end

    trait :bim do
      unit_name { "BIM" }
      unit_type { "Patrouille Maritime" }
    end

    # --- Role traits ---
    trait :inspector_general do
      role { :inspector_general }
      rank { "Inspecteur Général" }
    end

    trait :director_general do
      role { :director_general }
      rank { "Directeur Général" }
    end
  end
end
