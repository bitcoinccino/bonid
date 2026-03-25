# frozen_string_literal: true

FactoryBot.define do
  factory :name_change_request do
    association :user

    old_first_name  { "Jean" }
    old_middle_name { nil }
    old_last_name   { "Louis" }

    new_first_name  { "Jean-Pierre" }
    new_middle_name { nil }
    new_last_name   { "Dupont" }

    reason { "marriage" }
    status { :pending }

    after(:build) do |request|
      unless request.supporting_document.attached?
        request.supporting_document.attach(
          io: StringIO.new("fake document content"),
          filename: "marriage_certificate.pdf",
          content_type: "application/pdf"
        )
      end
    end

    trait :pending do
      status { :pending }
    end

    trait :approved do
      status { :approved }
      reviewed_at { Time.current }
      association :reviewed_by, factory: :admin_user
    end

    trait :rejected do
      status { :rejected }
      rejection_reason { "Supporting document is illegible. Please resubmit with a clearer copy." }
      reviewed_at { Time.current }
      association :reviewed_by, factory: :admin_user
    end

    trait :court_order do
      reason { "court_order" }
    end

    trait :error do
      reason { "error" }
    end

    trait :other_reason do
      reason { "other" }
      other_reason { "Legal adoption — name updated by court decree." }
    end
  end
end
