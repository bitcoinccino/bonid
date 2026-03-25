class CreateReviewers < ActiveRecord::Migration[8.0]
  def change
    create_table :reviewers do |t|
      t.timestamps
    end
  end
end
