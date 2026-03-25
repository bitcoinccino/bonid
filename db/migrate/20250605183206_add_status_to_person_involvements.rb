class AddStatusToPersonInvolvements < ActiveRecord::Migration[8.0]
  def change
    add_column :person_involvements, :status, :string
  end
end
