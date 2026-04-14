# frozen_string_literal: true

# An immutable, append-only record of a single cast vote.
#
# Contains NO personally identifiable information.
# The encrypted_choice can only be decrypted by the CEP multi-sig ceremony.
#
class ElectionBallot < ApplicationRecord
  belongs_to :election, class_name: "BonvoteElection"

  validates :nullifier, presence: true
  validates :position, presence: true, inclusion: { in: %w[president senator deputy] }
  validates :encrypted_choice, presence: true
  validates :zkp_commitment, presence: true
  validates :ballot_hash, presence: true, uniqueness: true
  validates :receipt_id, presence: true, uniqueness: true
  validates :channel, presence: true, inclusion: { in: %w[remote consulate in_person] }
  validates :cast_at, presence: true

  # Unique constraint: one nullifier per election (prevents double-voting)
  validates :nullifier, uniqueness: { scope: :election_id, message: "vote déjà enregistré" }

  scope :remote,    -> { where(channel: "remote") }
  scope :consulate, -> { where(channel: "consulate") }
  scope :in_person, -> { where(channel: "in_person") }
  scope :for_position, ->(pos) { where(position: pos) }
  scope :for_department, ->(code) { where(department_code: code) }
  scope :flagged,   -> { where(location_flagged: true) }
  scope :today,     -> { where("cast_at >= ?", Time.current.beginning_of_day) }
  scope :recent,    ->(n = 5) { order(cast_at: :desc).limit(n) }

  # Location label for public ticker (no PII — only department or country)
  # Returns [country_code, display_label] e.g. ["ht", "Ouest, HT"] or ["us", "Miami, US"]
  DEPARTMENT_LABELS = {
    "OU" => "Ouest", "ND" => "Nord", "SD" => "Sud", "AR" => "Artibonite",
    "NE" => "Nord-Est", "NO" => "Nord-Ouest", "SE" => "Sud-Est",
    "CE" => "Centre", "GA" => "Grande-Anse", "NI" => "Nippes"
  }.freeze

  CONSULATE_CITIES = {
    # United States
    "HT-EMB-WAS" => "Washington, D.C.", "HT-CON-MIA" => "Miami",
    "HT-CON-NYC" => "New York", "HT-CON-BOS" => "Boston",
    "HT-CON-CHI" => "Chicago", "HT-CON-ATL" => "Atlanta",
    "HT-CON-ORL" => "Orlando",
    # Canada
    "HT-EMB-OTT" => "Ottawa", "HT-CON-MTL" => "Montréal",
    # Dominican Republic
    "HT-EMB-SDQ" => "Santo Domingo", "HT-CON-BAR" => "Barahona",
    "HT-CON-DAJ" => "Dajabón", "HT-CON-HIG" => "Higüey",
    "HT-CON-STI" => "Santiago de los Caballeros",
    # Americas
    "HT-EMB-BUE" => "Buenos Aires", "HT-EMB-NAS" => "Nassau",
    "HT-EMB-BSB" => "Brasília", "HT-EMB-SCL" => "Santiago",
    "HT-EMB-BOG" => "Bogotá", "HT-EMB-HAV" => "La Havane",
    "HT-EMB-UIO" => "Quito", "HT-EMB-MEX" => "Mexico City",
    "HT-EMB-PTY" => "Panama City", "HT-CON-PBM" => "Paramaribo",
    "HT-EMB-CCS" => "Caracas",
    # Europe
    "HT-EMB-PAR" => "Paris", "HT-CON-PAR" => "Paris (Consulat)",
    "HT-EMB-BRU" => "Bruxelles", "HT-EMB-BER" => "Berlin",
    "HT-EMB-MAD" => "Madrid", "HT-EMB-LON" => "London",
    "HT-EMB-ROM" => "Rome (Saint-Siège)", "HT-EMB-ROM2" => "Rome",
    # Caribbean / Overseas territories
    "HT-CON-CAY" => "Cayenne", "HT-CON-PTP" => "Pointe-à-Pitre",
    "HT-CON-WIL" => "Willemstad", "HT-CON-ORA" => "Oranjestad",
    "HT-CON-TCI" => "Providenciales",
    # Asia & Middle East
    "HT-EMB-TYO" => "Tokyo", "HT-EMB-DOH" => "Doha",
    "HT-EMB-TPE" => "Taipei", "HT-EMB-HAN" => "Hanoi"
  }.freeze

  def ticker_location
    if department_code.present? && DEPARTMENT_LABELS[department_code]
      ["ht", "#{DEPARTMENT_LABELS[department_code]}, HT"]
    elsif consulate_id.present? && CONSULATE_CITIES[consulate_id]
      country = ip_country&.downcase || "us"
      ["#{country}", "#{CONSULATE_CITIES[consulate_id]}, #{ip_country || 'XX'}"]
    elsif ip_country.present?
      ["#{ip_country.downcase}", "#{ip_country}"]
    else
      ["ht", "Ayiti"]
    end
  end

  def time_ago_label
    seconds = (Time.current - cast_at).to_i
    case seconds
    when 0..59    then "now"
    when 60..119  then "1 min"
    when 120..3599 then "#{seconds / 60} min"
    when 3600..7199 then "1h"
    else "#{seconds / 3600}h"
    end
  end

  # Find by voter receipt hash (for "Vòt ou konte" verification)
  def self.verify(ballot_hash, election_id)
    ballot = find_by(ballot_hash: ballot_hash, election_id: election_id)
    if ballot
      {
        found: true,
        message: "Vòt ou anrejistre ak siksè.",
        timestamp: ballot.cast_at,
        position: ballot.position
      }
    else
      {
        found: false,
        message: "Bilten sa a pa jwenn nan rejis la.",
        timestamp: nil,
        position: nil
      }
    end
  end

  # Stats for CEP dashboard
  def self.stats(election_id)
    ballots = where(election_id: election_id)
    {
      total_votes: ballots.count,
      remote_votes: ballots.remote.count,
      consulate_votes: ballots.consulate.count,
      in_person_votes: ballots.in_person.count,
      flagged: ballots.flagged.count,
      by_position: ballots.group(:position).count,
      by_department: ballots.group(:department_code).count,
      by_channel: ballots.group(:channel).count,
      by_hour: ballots.group_by_hour(:cast_at, range: 24.hours.ago..Time.current).count,
      by_country: ballots.where.not(ip_country: [nil, ""]).group(:ip_country).count
    }
  rescue => e
    # group_by_hour requires groupdate gem; fallback
    {
      total_votes: ballots.count,
      remote_votes: ballots.remote.count,
      consulate_votes: ballots.consulate.count,
      in_person_votes: ballots.in_person.count,
      flagged: ballots.flagged.count,
      by_position: ballots.group(:position).count,
      by_department: ballots.group(:department_code).count,
      by_channel: ballots.group(:channel).count,
      by_country: ballots.where.not(ip_country: [nil, ""]).group(:ip_country).count
    }
  end
end
