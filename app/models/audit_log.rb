class AuditLog < ApplicationRecord
  belongs_to :record, polymorphic: true
end

