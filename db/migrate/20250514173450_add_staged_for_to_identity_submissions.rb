class AddStagedForToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :staged_for, :integer, default: 0, null: false
  end
end
