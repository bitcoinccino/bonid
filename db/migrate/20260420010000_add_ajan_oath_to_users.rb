# frozen_string_literal: true

# Adds per-user (agent) oath acknowledgment columns. Every ajan must read and
# sign the Ajan Oath before the Agent Portal dashboard becomes accessible.
#
# Why on users (not a separate table): the oath is a simple one-time-per-version
# acknowledgment with no rich state to track. Bumping AJAN_OATH_VERSION in the
# OathController forces every agent to re-accept on next login.
class AddAjanOathToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :ajan_oath_accepted_at, :datetime
    add_column :users, :ajan_oath_version,     :string, limit: 16
    add_index  :users, :ajan_oath_accepted_at
  end
end
