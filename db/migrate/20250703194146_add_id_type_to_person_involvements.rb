class AddIdTypeToPersonInvolvements < ActiveRecord::Migration[8.0]
  def change
    add_column :person_involvements, :id_type, :string
  end
end
