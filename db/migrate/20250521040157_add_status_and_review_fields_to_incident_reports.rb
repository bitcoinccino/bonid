class AddStatusAndReviewFieldsToIncidentReports < ActiveRecord::Migration[8.0]
  def change
    add_column :incident_reports, :status, :integer
    add_column :incident_reports, :review_comment, :text
    add_column :incident_reports, :reviewed_by_id, :integer
  end
end
