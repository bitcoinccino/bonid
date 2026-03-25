class AddMissingIdentityFieldsToPersonInvolvements < ActiveRecord::Migration[8.0]
  def change
    add_column :person_involvements, :cin, :string
    add_column :person_involvements, :cin_unique_id, :string
    add_column :person_involvements, :phone, :string
    add_column :person_involvements, :email, :string
    add_column :person_involvements, :address, :string
    add_column :person_involvements, :first_name, :string
    add_column :person_involvements, :middle_name, :string
    add_column :person_involvements, :last_name, :string
    add_column :person_involvements, :sex, :string
    add_column :person_involvements, :date_of_birth, :date
    add_column :person_involvements, :nationality, :string
    add_column :person_involvements, :id_issued_on, :date
    add_column :person_involvements, :id_expires_on, :date
    add_column :person_involvements, :place_of_birth_department_id, :integer
    add_column :person_involvements, :place_of_birth_commune_id, :integer
    add_column :person_involvements, :passport_number, :string
    add_column :person_involvements, :issuing_authority, :string
  end
end
