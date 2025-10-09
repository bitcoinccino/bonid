class VerificationRecordSerializer < ActiveModel::Serializer
  attributes :id, :record_type, :category, :status, :data, :metadata, :verified_at

  # Future: expose restricted fields based on access_level
end
