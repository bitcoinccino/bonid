# Name change requests become "correction requests": a citizen can also
# correct their date of birth (it's part of the BonID: DV-1989-…).
# applied_at marks when the approved correction was actually written to
# the user, after their re-verification was approved.
class AddDobAndAppliedAtToNameChangeRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :name_change_requests, :old_dob, :date
    add_column :name_change_requests, :new_dob, :date
    add_column :name_change_requests, :applied_at, :datetime
  end
end
