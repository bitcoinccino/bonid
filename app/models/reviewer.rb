# app/models/reviewer.rb
class Reviewer < ApplicationRecord
  belongs_to :user, optional: true

  validates :email, presence: true
  validate :must_have_verified_bonid

  def must_have_verified_bonid
    u = User.find_by(email: email)
    return if u&.bonid_verified?

    errors.add(:base, "You must verify your BonID first.")
  end
end
