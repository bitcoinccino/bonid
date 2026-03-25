# app/models/permission.rb
class Permission < ApplicationRecord
  has_and_belongs_to_many :roles

  validates :action, presence: true, uniqueness: true

  # Define constants for common permissions
  ACTIONS = %w[
    approve_submission
    reject_submission
    reset_submission
    invite_officer
    view_scan_logs
    verify_citizen
  ].freeze
end
