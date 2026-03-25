# frozen_string_literal: true

module VerificationRecords
  class EducationSerializer < ActiveModel::Serializer
    attributes :institution_name,
               :degree,
               :field_of_study,
               :start_date,
               :end_date,
               :graduation_year,
               :honors

    # Dynamically pull data keys from the JSON column
    def attributes(*args)
      data = object.data || {}
      super.each_key.with_object({}) do |key, hash|
        hash[key] = data[key.to_s] if data.key?(key.to_s)
      end
    end
  end
end
