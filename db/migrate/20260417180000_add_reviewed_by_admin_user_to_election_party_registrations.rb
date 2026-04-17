# frozen_string_literal: true

# Promote the "reviewed_by" audit trail on party registrations from a freeform
# string to a real AdminUser FK — matching the candidate-review model
# (ElectionCandidate#approved_by → AdminUser). The original string column stays
# for legacy rows written before CEP admin took over approval authority.
class AddReviewedByAdminUserToElectionPartyRegistrations < ActiveRecord::Migration[8.0]
  def change
    add_reference :election_party_registrations,
                  :reviewed_by_admin_user,
                  foreign_key: { to_table: :admin_users },
                  null: true
  end
end
