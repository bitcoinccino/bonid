# db/migrate/xxxx_add_live_selfie_fields_to_visitor_submissions.rb
class AddLiveSelfieFieldsToVisitorSubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :visitor_submissions, :selfie_captured_at, :datetime
    add_column :visitor_submissions, :liveness_metadata, :jsonb, default: {}
  end
end
