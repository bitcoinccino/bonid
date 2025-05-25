class ChangeUseCasesToArrayInPartnerApplications < ActiveRecord::Migration[7.1]
  def change
    remove_column :partner_applications, :use_cases, :text
    add_column :partner_applications, :use_cases, :string, array: true, default: []
  end
end
