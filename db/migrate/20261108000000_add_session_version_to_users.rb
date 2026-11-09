class AddSessionVersionToUsers < ActiveRecord::Migration[8.0]
  def change
    # Bumped by "sign out everywhere"; every citizen session carries the version
    # it was issued under and is dropped on the next request once they differ.
    add_column :users, :session_version, :integer, default: 0, null: false
  end
end
