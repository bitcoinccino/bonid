# app/models/partner_admin.rb
class PartnerAdmin < User
  # This lets Devise and Rails autoload the constant safely
  # without needing a new table.

  # Optional: constrain queries if you have a `role` or `roles` column
  default_scope { where(role: :partner_admin) if column_names.include?("role") rescue all }

  # Devise modules (you can copy from User if not auto-inherited)
  devise :database_authenticatable, :recoverable, :rememberable,
         :validatable, :trackable, :timeoutable
end
