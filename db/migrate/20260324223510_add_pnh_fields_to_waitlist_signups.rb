class AddPnhFieldsToWaitlistSignups < ActiveRecord::Migration[8.0]
  def change
    add_column :waitlist_signups, :rank, :string
    add_column :waitlist_signups, :unit_type, :string
    add_column :waitlist_signups, :unit_name, :string
  end
end
