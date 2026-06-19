# frozen_string_literal: true

class AddLaunchedAtToCommunes < ActiveRecord::Migration[8.0]
  def change
    add_column :communes, :launched_at, :datetime
  end
end
