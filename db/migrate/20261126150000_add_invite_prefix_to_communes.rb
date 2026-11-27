# frozen_string_literal: true

# Optional 3-letter prefix for invite codes (DEL-7KQ2XA). Separate from
# communes.code, which holds the administrative code (HT0112). When blank,
# InviteCode derives a prefix from the commune name.
class AddInvitePrefixToCommunes < ActiveRecord::Migration[8.0]
  def change
    add_column :communes, :invite_prefix, :string, limit: 4
    add_index :communes, :invite_prefix, unique: true
  end
end
