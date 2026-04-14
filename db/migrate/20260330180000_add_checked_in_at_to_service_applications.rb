class AddCheckedInAtToServiceApplications < ActiveRecord::Migration[7.1]
  def change
    add_column :service_applications, :checked_in_at, :datetime
  end
end
