# app/models/concerns/record_schemas/property_schema.rb
module RecordSchemas
  module PropertySchema
    extend ActiveSupport::Concern

    included do
      store_accessor :data,
        :title_number,
        :property_type,
        :address,
        :area_m2,
        :owner_since,
        :market_value_htg,
        :cadastral_map_ref,
        :registered_authority

      validate :validate_property_fields
    end

    private

    def validate_property_fields
      errors.add(:data, "Title number required") if title_number.blank?
      errors.add(:data, "Address required") if address.blank?
    end
  end
end
