# frozen_string_literal: true

class VerificationRecordSerializer < ActiveModel::Serializer
  attributes :id,
             :record_type,
             :category,
             :status,
             :access_level,
             :source,
             :notes,
             :verifier_id,
             :verifier_type,
             :data,
             :metadata,
             :created_at,
             :updated_at,
             :summary

  belongs_to :user

  def created_at
    object.created_at&.iso8601
  end

  def updated_at
    object.updated_at&.iso8601
  end

  def summary
    object.try(:summary)
  end

  # =========================================
  # 🔁 Dynamic Sub-Serializer Delegation
  # =========================================
  def attributes(*args)
    base_attrs = super
    subtype_class = resolve_subtype_serializer

    if subtype_class
      subtype = subtype_class.new(object)
      base_attrs.merge!(subtype.attributes)
    end

    base_attrs
  end

  private

  # Dynamically resolves a subtype serializer based on record_type
  def resolve_subtype_serializer
    return unless object.record_type.present?

    # e.g. "business" → VerificationRecord::BusinessSerializer
    klass_name = "VerificationRecord::#{object.record_type.camelize}Serializer"
    Object.const_get(klass_name) if Object.const_defined?(klass_name)
  rescue NameError
    nil
  end
end
