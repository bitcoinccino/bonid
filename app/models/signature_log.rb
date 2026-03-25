# app/models/signature_log.rb
class SignatureLog < ApplicationRecord
  belongs_to :identity_submission
  belongs_to :user
  belongs_to :verifier, class_name: "AdminUser", optional: true

  validates :action, presence: true
end
