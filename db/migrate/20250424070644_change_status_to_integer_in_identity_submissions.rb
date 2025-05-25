class ChangeStatusToIntegerInIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    change_column :identity_submissions, :status, :integer, using: 'status::integer'
  end
end
