class Commune < ApplicationRecord
  belongs_to :department
  belongs_to :arrondissement
  has_many :communal_sections
  validates :postal_code, presence: true

  # Below this many real signups we use "be among the first" framing
  # instead of showing a near-empty number.
  SOCIAL_PROOF_THRESHOLD = 25

  # Real waitlist signups for this commune — no fabricated padding.
  # Single source of truth for both the signup wizard and the
  # confirmation page so the two never disagree.
  def display_signups
    WaitlistSignup.where(commune_id: id).count
  end

  # Go live: everyone in this commune (waiting and future signups) now
  # skips the waitlist gate. Stamps the most recent go-live time.
  def launch!
    update!(launched: true, launched_at: Time.current)
  end

  # Reverse a launch — new signups here wait again. The historical
  # launched_at is preserved for reference.
  def unlaunch!
    update!(launched: false)
  end
end