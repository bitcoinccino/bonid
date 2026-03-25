# app/models/admin_user.rb
class AdminUser < ApplicationRecord
  # === Roles via Rolify ===
  rolify role_cascade: :children, join_table: :admin_users_roles

  # === Devise Modules ===
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  # === Associations ===
  has_many :approved_schemas, class_name: "PartnerSchema", foreign_key: :approved_by_id, dependent: :nullify

  # === Validations ===
  validates :email, presence: true, uniqueness: true

  # === Devise Overrides (Optional) ===
  def after_confirmation
    # Custom post-confirmation logic, e.g., send welcome email
    super
  end
end
