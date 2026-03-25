# db/migrate/XXXXXXXXXXXXXX_change_user_id_null_on_visitor_submissions.rb
class ChangeUserIdNullOnVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    change_column_null :visitor_submissions, :user_id, true
  end
end
