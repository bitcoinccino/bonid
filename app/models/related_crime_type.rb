# app/models/related_crime_type.rb
class RelatedCrimeType < ApplicationRecord
  belongs_to :crime_type
  belongs_to :related_crime_type, class_name: "CrimeType"

  validates :crime_type_id, uniqueness: { scope: :related_crime_type_id }
  validates :relationship_type, presence: true
  validates :correlation_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  RELATIONSHIP_TYPES = %w[
    often_together
    escalation
    subset
    precursor
    same_pattern
  ].freeze

  validates :relationship_type, inclusion: { in: RELATIONSHIP_TYPES }

  scope :strong_correlation, -> { where("correlation_score >= ?", 0.7) }
  scope :by_type, ->(type) { where(relationship_type: type) }
end
