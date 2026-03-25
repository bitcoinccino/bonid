class MakeNameNullableInWaitlistSignups < ActiveRecord::Migration[8.0]
  def change
    change_column_null :waitlist_signups, :first_name, true
    change_column_null :waitlist_signups, :last_name, true
  end
end
