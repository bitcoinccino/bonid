# frozen_string_literal: true

class AddPublicIdToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :public_id, :uuid, default: "gen_random_uuid()", null: false
    add_index  :visitor_submissions, :public_id, unique: true
  end
end
