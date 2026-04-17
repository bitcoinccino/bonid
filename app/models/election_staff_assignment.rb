# frozen_string_literal: true

# Links CEP team members to specific electoral bodies (BED/BEC/BCEV).
#
# OAS Recommendation: "The Mission recommends that the CEP take the measures
# necessary to ensure that all polling station workers are fully trained days
# before the election."
#
# Each staff member must have a verified BonID and be assigned to a specific
# station — no floating assignments like the 2015 party rep fiasco.
#
class ElectionStaffAssignment < ApplicationRecord
  ROLES = GovernmentRoleConstants.roles_for("cep").map { |r| r[:key] }.freeze

  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :user
  belongs_to :election_body

  validates :role, presence: true
  validates :status, inclusion: { in: %w[assigned active completed removed] }
  validates :user_id, uniqueness: { scope: [ :election_id, :election_body_id ], message: "deja asiye nan biwo sa a" }

  scope :active,    -> { where(status: %w[assigned active]) }
  scope :checked_in, -> { where.not(checked_in_at: nil) }
  scope :for_role,  ->(role) { where(role: role) }

  def assigned?  = status == "assigned"
  def active?    = status == "active"
  def completed? = status == "completed"

  # Staff checks in at their station on election day
  def check_in!
    update!(status: "active", checked_in_at: Time.current, identity_verified: true)
  end

  # Staff checks out after voting closes
  def check_out!
    update!(status: "completed", checked_out_at: Time.current)
  end

  # Role label via GovernmentRoleConstants
  def role_label
    GovernmentRoleConstants.role_label("cep", role)
  end

  # Stats for CEP staffing dashboard
  def self.stats_for(election_id)
    assignments = where(election_id: election_id)
    {
      total: assignments.count,
      checked_in: assignments.checked_in.count,
      by_role: assignments.group(:role).count,
      by_status: assignments.group(:status).count,
      coverage: assignments.active.select(:election_body_id).distinct.count
    }
  end
end
