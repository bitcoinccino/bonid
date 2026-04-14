# frozen_string_literal: true

# The CEP's decentralized electoral hierarchy:
#
#   CEP (national, 9-member council)
#    └── BED (Bureau Electoral Départemental) — 10 total, one per department
#         └── BEC (Bureau Electoral Communal) — one per commune
#              └── BCEV (Bureau Electoral de Vote) — individual polling stations
#
# OAS Report: "Departmental Electoral Offices (BED) & Communal Electoral Offices (BEC)
# handle the local logistics of the election."
#
class ElectionBody < ApplicationRecord
  BODY_TYPES = %w[bed bec bcev].freeze

  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :parent_body, class_name: "ElectionBody", optional: true
  has_many   :child_bodies, class_name: "ElectionBody", foreign_key: :parent_body_id, dependent: :destroy
  has_many   :election_staff_assignments, dependent: :destroy
  has_many   :election_accreditations, foreign_key: :assigned_body_id, dependent: :nullify
  has_many   :election_disputes, dependent: :nullify

  validates :body_type, presence: true, inclusion: { in: BODY_TYPES }
  validates :code, presence: true, uniqueness: { scope: :election_id }
  validates :name, presence: true
  validates :status, inclusion: { in: %w[active closed suspended] }

  scope :beds,  -> { where(body_type: "bed") }
  scope :becs,  -> { where(body_type: "bec") }
  scope :bcevs, -> { where(body_type: "bcev") }
  scope :active, -> { where(status: "active") }
  scope :for_department, ->(code) { where(department_code: code) }

  def bed?  = body_type == "bed"
  def bec?  = body_type == "bec"
  def bcev? = body_type == "bcev"

  # Human-readable type label (Kreyòl)
  def type_label
    { "bed" => "Biwo Elektoral Depatmantal",
      "bec" => "Biwo Elektoral Kominal",
      "bcev" => "Biwo Elektoral de Vòt" }[body_type]
  end

  # Seed the standard Haiti electoral hierarchy for an election.
  # Creates 10 BEDs (one per department) and BECs for each commune.
  def self.seed_haiti_2026!(election)
    departments = ::Election::BallotRoutingService::DEPARTMENTS

    departments.each do |code, name|
      bed = create!(
        election: election,
        body_type: "bed",
        code: "BED-#{code}",
        name: "Biwo Elektoral Depatmantal — #{name}",
        department_code: code,
        department_name: name,
        status: "active"
      )

      # Create BECs for each commune in this department
      if defined?(Commune) && Commune.respond_to?(:includes)
        communes = Commune.includes(:arrondissement)
                          .where(arrondissements: { department_id: Department.find_by(name: name)&.id })

        communes.find_each do |commune|
          create!(
            election: election,
            body_type: "bec",
            code: "BEC-#{code}-#{commune.id}",
            name: "Biwo Elektoral Kominal — #{commune.name}",
            department_code: code,
            department_name: name,
            commune_id: commune.id,
            arrondissement_id: commune.arrondissement_id,
            parent_body: bed,
            status: "active"
          )
        end
      end
    end
  end
end
