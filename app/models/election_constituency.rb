# frozen_string_literal: true

# Maps geographic areas to elected positions for an election.
#
# Haiti 2026:
#   - 1 presidential constituency (national)
#   - 10 senate constituencies (1 per department, 3 seats each, 1/3 rotation)
#   - 99 deputy constituencies (single-member, by commune/arrondissement)
#
class ElectionConstituency < ApplicationRecord
  belongs_to :election, class_name: "BonvoteElection"
  has_many :election_candidates, dependent: :destroy

  validates :position, presence: true, inclusion: { in: %w[president senator deputy] }
  validates :constituency_name, presence: true
  validates :seats, numericality: { greater_than: 0 }
  validates :electoral_system, presence: true

  scope :for_position, ->(pos) { where(position: pos) }
  scope :up_for_election, -> { where(up_for_election: true) }
  scope :for_department, ->(code) { where(department_code: code) }

  # Seed the standard Haiti constituencies for a general election.
  # Senate: 10 departments, only seats_up (1/3 rotation) are up_for_election.
  # Deputy: 99 single-member constituencies mapped to communes.
  def self.seed_haiti_2026!(election, senate_seats_up:)
    departments = ::Election::BallotRoutingService::DEPARTMENTS

    # Presidential — 1 national constituency
    create!(
      election: election,
      position: "president",
      constituency_name: "Prezidan Repiblik d'Ayiti",
      seats: 1,
      electoral_system: "absolute_majority_two_round"
    )

    # Senate — 10 departments, seats_up of 3 per dept are up this cycle
    departments.each do |code, name|
      create!(
        election: election,
        position: "senator",
        department_code: code,
        department_name: name,
        constituency_name: "Senatè — #{name}",
        seats: senate_seats_up,
        up_for_election: true,
        electoral_system: "absolute_majority_two_round"
      )
    end

    # Deputy — 99 seats. Each commune/arrondissement = 1 constituency.
    # In production, this would be seeded from CEP constituency map data.
    # Placeholder: create one per commune from the Commune model.
    if defined?(Commune) && Commune.respond_to?(:includes)
      Commune.includes(:arrondissement).find_each do |commune|
        dept_code = departments.key(commune.arrondissement&.department&.name)
        create!(
          election: election,
          position: "deputy",
          department_code: dept_code,
          department_name: commune.arrondissement&.department&.name,
          commune_id: commune.id,
          arrondissement_id: commune.arrondissement_id,
          constituency_name: "Depite — #{commune.name}",
          seats: 1,
          up_for_election: true,
          electoral_system: "absolute_majority_two_round"
        )
      end
    end
  end
end
