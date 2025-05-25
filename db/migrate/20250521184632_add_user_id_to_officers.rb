# db/migrate/xxxx_add_user_id_to_officers.rb
class AddUserIdToOfficers < ActiveRecord::Migration[7.1]
  def change
    add_reference :officers, :user, foreign_key: true, null: true
  end
end
