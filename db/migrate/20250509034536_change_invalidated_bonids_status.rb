class ChangeInvalidatedBonidsStatus < ActiveRecord::Migration[7.0]
  def up
    # Only update rejected submissions with a reset_request_status of 'approved'
    IdentitySubmission.where(status: 2, reset_request_status: 1).update_all(status: 3)
  end

  def down
    # Revert them if needed
    IdentitySubmission.where(status: 3, reset_request_status: 1).update_all(status: 2)
  end
end
