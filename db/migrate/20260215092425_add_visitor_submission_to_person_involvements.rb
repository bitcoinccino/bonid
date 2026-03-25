class AddVisitorSubmissionToPersonInvolvements < ActiveRecord::Migration[8.0]
  def change
    add_reference :person_involvements, :visitor_submission, null: true, foreign_key: true
  end
end
