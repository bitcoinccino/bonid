class AddMissingDeviseFieldsToOfficers < ActiveRecord::Migration[7.1]
  def change
    change_table :officers, bulk: true do |t|
      t.string   :encrypted_password, null: false, default: "" unless column_exists?(:officers, :encrypted_password)
      t.string   :reset_password_token unless column_exists?(:officers, :reset_password_token)
      t.datetime :reset_password_sent_at unless column_exists?(:officers, :reset_password_sent_at)
      t.datetime :remember_created_at unless column_exists?(:officers, :remember_created_at)
    end

    add_index :officers, :reset_password_token, unique: true unless index_exists?(:officers, :reset_password_token)
  end
end
