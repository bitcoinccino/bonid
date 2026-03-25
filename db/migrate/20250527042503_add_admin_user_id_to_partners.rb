class AddAdminUserToPartners < ActiveRecord::Migration[7.1]
  def change
    add_reference :partners, :admin_user, foreign_key: { to_table: :users }, index: true
  end
end
