# frozen_string_literal: true

# 🇭🇹 BonID — Default Record Templates
# Provides JSON skeletons for initializing new verification records.
# Each template predefines empty keys expected by the schema.
#
# Usage:
#   include RecordSchemas::DefaultTemplates
#   data = default_template_for("property")
#
# Automatically ensures all record types return a consistent hash
# and are safe to merge into @record.data during initialization.
module RecordSchemas
  module DefaultTemplates
    extend ActiveSupport::Concern

    included do
      # For convenience in models that include this concern
      def ensure_default_data!
        self.data ||= default_template_for(record_type)
      end
    end

    def default_template_for(type)
      type = type.to_s.downcase

      case type
      when "property"
        {
          "property" => {
            "title_number"      => "",
            "cadastral_ref"     => "",
            "commune"           => "",
            "section_communal"  => "",
            "location"          => "",
            "property_type"     => "",
            "area_m2"           => "",
            "owner_since"       => "",
            "zoning_use"        => ""
          },
          "valuation" => {
            "market_value_htg"    => "",
            "last_appraisal_date" => ""
          },
          "buyer" => {
            "name"     => "",
            "type"     => "",
            "email"    => "",
            "phone"    => "",
            "address"  => ""
          },
          "seller" => {
            "name"     => "",
            "type"     => "",
            "address"  => ""
          },
          "legal" => {
            "notary_name"      => "",
            "registration_ref" => ""
          },
          "documents" => []
        }

      when "business"
        {
          "business" => {
            "registration_number" => "",
            "legal_name"          => "",
            "sector"              => "",
            "address"             => ""
          },
          "owner" => {
            "name"  => "",
            "email" => "",
            "phone" => ""
          }
        }

      when "health"
        {
          "health" => {
            "facility_name" => "",
            "record_type"   => "",
            "notes"         => ""
          }
        }

      when "land_transaction"
        {
          "property" => {
            "location" => "",
            "parcel_number" => ""
          },
          "buyer" => { "name" => "", "type" => "" },
          "seller" => { "name" => "", "type" => "" },
          "valuation" => {
            "sale_price_htg" => "",
            "taxes_htg"      => ""
          }
        }

      when "fiscal_receipt"
        {
          "receipt" => {
            "receipt_number"  => "",
            "tax_type"        => "",
            "amount_htg"      => "",
            "payment_date"    => "",
            "fiscal_year"     => "",
            "dgi_office_code" => "",
            "payment_method"  => "",
            "cashier_id"      => "",
            "batch_number"    => ""
          },
          "payer" => {
            "name"  => "",
            "nif"   => "",
            "bonid" => ""
          },
          "consumption" => {
            "consumed"               => false,
            "consumed_at"            => nil,
            "consumed_by_agency"     => nil,
            "consumed_by_officer_id" => nil
          },
          "documents" => []
        }

      else
        {}
      end
    end
  end
end
