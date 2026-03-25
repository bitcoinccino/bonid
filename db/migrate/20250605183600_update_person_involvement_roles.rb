# db/migrate/20250605143400_update_person_involvement_roles.rb
class UpdatePersonInvolvementRoles < ActiveRecord::Migration[8.0]
  def up
    PersonInvolvement.where(role: "other").update_all(role: "unknown")
  end

  def down
    PersonInvolvement.where(role: "unknown").update_all(role: "other")
  end
end

