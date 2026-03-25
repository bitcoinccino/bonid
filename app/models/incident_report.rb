require "rqrcode"
require "base64"
require "csv"
require "digest/sha2"

class IncidentReport < ApplicationRecord
  include CrimeConstants

  # Use UUID for URL routing instead of integer ID (security enhancement)
  def to_param
    uuid
  end

  belongs_to :officer
  belongs_to :partner, optional: true
  belongs_to :reviewed_by, class_name: "AdminUser", optional: true
  belongs_to :crime_type_record, class_name: "CrimeType", optional: true
  has_many :person_involvements, dependent: :destroy, inverse_of: :incident_report
  has_one :address, as: :addressable, dependent: :destroy
  has_many :audit_logs, as: :record, dependent: :destroy

  # Case linking
  has_many :incident_links, dependent: :destroy
  has_many :linked_incidents, through: :incident_links, source: :linked_incident
  has_many :incident_reviews, dependent: :destroy
  has_many :suspect_alerts, foreign_key: :source_incident_id

  has_many_attached :media

  # Server-side evidence validation (matches client-side limits)
  validate :validate_media_files

  accepts_nested_attributes_for :address, allow_destroy: true
  accepts_nested_attributes_for :person_involvements, allow_destroy: true, reject_if: :all_blank

  enum :report_status, { pending: 0, approved: 1, flagged: 2 }

  before_save :resolve_crime_type_record
  after_create :sign_report!
  after_update :re_sign_if_submitted!

  validates :crime_type, :occurred_at, :description, presence: true
  validates :signed_by_badge_id, presence: {
    message: "L'attestation de signature est requise pour soumettre un rapport officiel."
  }, if: :status_submitted?
  # === Scopes ===
  scope :drafts,    -> { where(status: :draft) }
  scope :submitted, -> { where(status: :submitted) }

  # Unit-scoped query — returns reports filed by officers of a specific unit within a partner.
  # Used by the partner portal admin controllers when the admin is unit-scoped (:unit scope).
  scope :for_unit, ->(unit_name, partner_id) {
    officer_ids = Officer.where(partner_id: partner_id, unit_name: unit_name).pluck(:id)
    where(officer_id: officer_ids)
  }

  # "Need to Know" — Joint Task Force crime types (kidnapping, child abduction).
  # Used in OfficerAccessControl#joint_task_force_reports.
  scope :joint_task_force, -> {
    where(crime_type: OfficerConstants::UNIT_ACCESS_SCOPE[:joint_task_force][:trigger_crime_types])
  }

  # Internal Affairs only — police brutality reports.
  # Never visible to line officers; only Inspector General role.
  scope :internal_affairs_only, -> {
    where(crime_type: OfficerConstants::UNIT_ACCESS_SCOPE[:internal_affairs][:trigger_crime_types])
  }

  # === Constants ===
  CRIME_TYPES = {
    violent_crimes: [ "Homicide", "Sexual Violence", "Kidnapping", "Assault", "Torture", "Lynching", "Police Brutality", "Domestic Violence", "Child Abduction", "Hate Crimes", "Gang Violence", "Mutilation", "Armed Assault", "Human Sacrifice", "Stalking", "Mass Murder", "Serial Killing", "Ethnic Cleansing" ],
    property_crimes: [ "Armed Robbery", "Burglary", "Theft", "Carjacking", "Home Invasion", "Vandalism", "Arson", "Larceny", "Shoplifting", "Fencing Stolen Goods", "Art Theft", "Livestock Theft" ],
    organized_crime: [ "Drug Trafficking", "Human Trafficking", "Arms Trafficking", "Organized Crime", "Racketeering", "Extortion", "Money Laundering", "Piracy", "Contract Killing", "Illegal Betting Syndicates", "Protection Rackets", "Organ Harvesting", "Cyber Extortion", "Sex Trafficking", "Labor Trafficking", "Child Trafficking", "Forced Marriage Trafficking", "Debt Bondage Trafficking", "Nuclear Material Trafficking", "Chemical Weapons Trafficking" ],
    economic_crimes: [ "Financial Fraud", "Embezzlement", "Corruption", "Counterfeiting", "Identity Theft", "Illegal Gambling", "Tax Evasion", "Bribery", "Ponzi Schemes", "Insider Trading", "Corporate Espionage", "Price Fixing", "Workplace Bribery", "Nepotism", "Cronyism", "Kickback Schemes", "Falsified Expense Reports", "Abuse of Authority" ],
    smuggling_and_trafficking: [ "Fuel Smuggling", "Smuggling of Goods", "Wildlife Trafficking", "Blackmail", "Antiquities Smuggling", "Tobacco Smuggling", "Pharmaceutical Trafficking", "Human Organ Trafficking", "Exotic Pet Trafficking" ],
    social_and_emerging_crimes: [ "Child Exploitation", "Forced Displacement", "Environmental Crime", "Election-Related Violence", "Prison Breaks", "Cybercrime", "Public Disorder", "Terrorism", "Land Disputes", "Revenge Pornography", "Online Harassment", "Deepfake Fraud", "Cryptocurrency Scams", "Food Contamination", "Vigilantism", "Bioterrorism", "Cyberterrorism", "Ecocide", "Illegal Protest Assembly", "Protest Incitement", "Protest-Related Arson", "Protest-Related Assault", "Barricade Destruction" ],
    traffic_and_minor_infractions: [ "Traffic Violation", "Driving Without License", "Vehicle Registration Violation", "Public Nuisance", "Littering", "Trespassing", "Minor Vandalism", "Disorderly Conduct", "Jaywalking", "Illegal Parking", "Noise Violations", "Public Intoxication", "Loitering", "Petty Theft" ],
    political_and_state_crimes: [ "Treason", "Espionage", "Sedition", "Election Tampering", "State-Sanctioned Violence", "Propaganda Dissemination", "Coup d'État", "War Crimes", "Genocide", "Crimes Against Humanity", "State-Sponsored Terrorism", "Protest-Driven Sedition", "Anti-Government Protest Conspiracy" ],
    public_health_and_safety_crimes: [ "Illegal Drug Manufacturing", "Food Adulteration", "Public Health Violations", "Hazardous Waste Dumping", "Unlicensed Medical Practice", "Quarantine Violations", "Vaccine Fraud", "Biological Weapons Use" ],
    technology_and_data_crimes: [ "Data Breaches", "Hacking", "Phishing", "Ransomware Attacks", "Dark Web Trafficking", "Software Piracy", "AI Manipulation", "Digital Forgery", "Critical Infrastructure Hacking" ],
    intellectual_property_crimes: [ "Copyright Infringement", "Trademark Counterfeiting", "Patent Infringement", "Trade Secret Theft", "Counterfeit Goods Distribution", "Digital Piracy", "Brand Impersonation", "Design Right Violation", "Music Copyright Infringement", "Unauthorized Music Streaming", "Music Plagiarism", "Bootleg Recordings" ],
    prison_crimes: [ "Inmate Homicide", "Prison Assault", "Contraband Smuggling in Prison", "Prison Guard Corruption", "Inmate Extortion", "Prison Gang Activity", "Sexual Exploitation in Prison", "Escape Conspiracy" ]
  }.freeze

  CRIME_CODES = {
    "homicide" => "HOMO", "sexual violence" => "SEXV", "kidnapping" => "KIDN", "assault" => "ASSA",
    "torture" => "TORT", "lynching" => "LYNC", "police brutality" => "POLB", "domestic violence" => "DOMV",
    "child abduction" => "CHAB", "hate crimes" => "HATE", "gang violence" => "GANG", "mutilation" => "MUTI",
    "armed assault" => "ARMA", "human sacrifice" => "HUSR", "stalking" => "STAL", "mass murder" => "MASM",
    "serial killing" => "SERK", "ethnic cleansing" => "ETHC", "armed robbery" => "AROB", "burglary" => "BURG",
    "theft" => "THEF", "carjacking" => "CARJ", "home invasion" => "HOME", "vandalism" => "VAND",
    "arson" => "ARSO", "larceny" => "LARC", "shoplifting" => "SHOP", "fencing stolen goods" => "FENC",
    "art theft" => "ARTT", "livestock theft" => "LIVE", "drug trafficking" => "DRUG", "human trafficking" => "HUMT",
    "arms trafficking" => "ARMT", "organized crime" => "ORGC", "racketeering" => "RACK", "extortion" => "EXTO",
    "money laundering" => "MONE", "piracy" => "PIRA", "contract killing" => "CONT", "illegal betting syndicates" => "BETS",
    "protection rackets" => "PROT", "organ harvesting" => "ORGH", "cyber extortion" => "CYBE", "sex trafficking" => "SEXT",
    "labor trafficking" => "LABT", "child trafficking" => "CHTR", "forced marriage trafficking" => "FMAR",
    "debt bondage trafficking" => "DEBT", "nuclear material trafficking" => "NUCT", "chemical weapons trafficking" => "CHEM",
    "financial fraud" => "FRAU", "embezzlement" => "EMBE", "corruption" => "CORR", "counterfeiting" => "COUN",
    "identity theft" => "IDEN", "illegal gambling" => "GAMB", "tax evasion" => "TAXE", "bribery" => "BRIB",
    "ponzi schemes" => "PONZ", "insider trading" => "INSI", "corporate espionage" => "ESPI", "price fixing" => "PRIC",
    "workplace bribery" => "WORK", "nepotism" => "NEPO", "cronyism" => "CRON", "kickback schemes" => "KICK",
    "falsified expense reports" => "FALS", "abuse of authority" => "ABUS", "fuel smuggling" => "FUEL",
    "smuggling of goods" => "SMUG", "wildlife trafficking" => "WILD", "blackmail" => "BLAC",
    "antiquities smuggling" => "ANTI", "tobacco smuggling" => "TOBA", "pharmaceutical trafficking" => "PHAR",
    "human organ trafficking" => "HORG", "exotic pet trafficking" => "EXOT", "child exploitation" => "CHEX",
    "forced displacement" => "FORC", "environmental crime" => "ENVI", "election-related violence" => "ELEC",
    "prison breaks" => "PRIS", "cybercrime" => "CYBR", "public disorder" => "PUBD", "terrorism" => "TERR",
    "land disputes" => "LAND", "revenge pornography" => "REVP", "online harassment" => "HARA",
    "deepfake fraud" => "DEEP", "cryptocurrency scams" => "CRYP", "food contamination" => "FOOD",
    "vigilantism" => "VIGI", "bioterrorism" => "BIOT", "cyberterrorism" => "CYBT", "ecocide" => "ECOC",
    "illegal protest assembly" => "PROA", "protest incitement" => "PROI", "protest-related arson" => "PRAR",
    "protest-related assault" => "PRAS", "barricade destruction" => "BARR", "traffic violation" => "TRAF",
    "driving without license" => "DRIV", "vehicle registration violation" => "VEHI", "public nuisance" => "NUIS",
    "littering" => "LITT", "trespassing" => "TRES", "minor vandalism" => "MINV", "disorderly conduct" => "DISC",
    "jaywalking" => "JAYW", "illegal parking" => "PARK", "noise violations" => "NOIS", "public intoxication" => "INTO",
    "loitering" => "LOIT", "petty theft" => "PETT", "treason" => "TREA", "espionage" => "ESPO",
    "sedition" => "SEDI", "election tampering" => "TAMP", "state-sanctioned violence" => "STAT",
    "propaganda dissemination" => "PROP", "coup d'état" => "COUP", "war crimes" => "WARC",
    "genocide" => "GENO", "crimes against humanity" => "CRIM", "state-sponsored terrorism" => "STSP",
    "protest-driven sedition" => "PSED", "anti-government protest conspiracy" => "ANTI",
    "illegal drug manufacturing" => "DRGM", "food adulteration" => "FOAD", "public health violations" => "HEAL",
    "hazardous waste dumping" => "WAST", "unlicensed medical practice" => "MEDI", "quarantine violations" => "QUAR",
    "vaccine fraud" => "VACC", "biological weapons use" => "BIOW", "data breaches" => "DATA",
    "hacking" => "HACK", "phishing" => "PHIS", "ransomware attacks" => "RANS", "dark web trafficking" => "DARK",
    "software piracy" => "SOFT", "ai manipulation" => "AIMA", "digital forgery" => "DIGI",
    "critical infrastructure hacking" => "INFR", "copyright infringement" => "COPY",
    "trademark counterfeiting" => "TRAD", "patent infringement" => "PATE", "trade secret theft" => "SECR",
    "counterfeit goods distribution" => "GOOD", "digital piracy" => "DPIR", "brand impersonation" => "BRAN",
    "design right violation" => "DESI", "music copyright infringement" => "MUSC",
    "unauthorized music streaming" => "STRM", "music plagiarism" => "PLAG", "bootleg recordings" => "BOOT",
    "inmate homicide" => "INHO", "prison assault" => "PRIA", "contraband smuggling in prison" => "SMUP",
    "prison guard corruption" => "GUAR", "inmate extortion" => "INEX", "prison gang activity" => "PGAN",
    "sexual exploitation in prison" => "SEXP", "escape conspiracy" => "ESCA"
  }.freeze

    # === Validations ===
    validates :report_id, :crime_type, :occurred_at, :description, presence: true
    validates :crime_type, inclusion: { in: CRIME_TYPES.values.flatten }
    validates_associated :address, if: -> { address.present? }
    validate :validate_address_details, if: -> { address.present? }
    validate :validate_person_involvements, unless: -> { person_involvements.empty? }

    # === Callbacks ===
    before_validation :set_partner_from_officer
    before_validation :generate_report_id, on: :create
    before_validation :set_submission_timestamp
    before_validation :set_officer_details
    before_create :generate_qr_code_and_case_number
    after_create :log_badge_id
    after_create :notify_involved_citizens, if: :status_submitted?

  # === Class Methods ===
  def self.to_csv
    attributes = %w[
      report_id crime_type occurred_at description officer_name officer_bonid officer_unit
      bonid_case_number submitted_at created_at
    ]

    CSV.generate(headers: true) do |csv|
      csv << attributes + [ "person_name", "person_bonid", "person_role", "person_status" ]
      all.each do |report|
        report.person_involvements.each do |pi|
          csv << attributes.map { |attr| report.send(attr) } + [
            pi.name || pi.user&.full_name,
            pi.bonid,
            pi.role,
            pi.status
          ]
        end
      end
    end
  end

  # === Instance Methods ===
  def generate_report_id
    return if report_id.present?

    date_str  = occurred_at&.strftime("%Y%m%d") || Time.current.strftime("%Y%m%d")
    crime_str = crime_code
    # Use departmental directorate (DDO, DDN, etc.) as geographic command identifier
    # Fall back to first 5 chars of unit_name, then "PNH"
    dir_str   = officer&.department_directorate.presence ||
                officer&.unit_name&.upcase&.slice(0, 5).presence ||
                "PNH"
    badge_str = Digest::SHA256.hexdigest(officer&.badge_id || "NONE")[0..5].upcase
    suffix    = SecureRandom.alphanumeric(3).upcase
    candidate_id = "PNH-#{dir_str}-#{crime_str}-#{date_str}-#{badge_str}-#{suffix}"
    5.times do
      unless IncidentReport.exists?(report_id: candidate_id)
        self.report_id = candidate_id
        return
      end
      Rails.logger.warn("Report ID collision detected for #{candidate_id}")
      suffix       = SecureRandom.alphanumeric(3).upcase
      candidate_id = "PNH-#{dir_str}-#{crime_str}-#{date_str}-#{badge_str}-#{suffix}"
    end
    Rails.logger.error("Failed to generate unique report_id for #{candidate_id}")
    raise "Unable to generate unique report_id after retries"
  end


def full_location
  return "Unknown Location" unless address

  [ address.street_address, address.locality, address.postal_code, address.commune&.name, address.department&.name ].compact.join(", ")
end

def crime_severity_level
  CrimeConstants::CRIME_SEVERITY[crime_type.to_s.downcase] || 1
end

# Returns the Haitian Penal Code article reference for this crime type
def penal_code_articles
  CrimeConstants::CRIME_ARTICLES[crime_type.to_s.downcase]
end

def crime_level
  level = CRIME_SEVERITY[crime_type.to_s.downcase]
  SEVERITY_LABELS[level] if level
end

enum :status, {
  draft: "draft",                  # Officer is still editing
  submitted: "submitted",          # Submitted and awaiting review
  under_review: "under_review",    # Admin/superior is reviewing
  approved: "approved",            # Accepted as valid report
  rejected: "rejected",            # Sent back to officer
  escalated: "escalated",          # Escalated to higher authority
  archived: "archived"             # Closed or no further action
}, prefix: true


 # Allow Ransack to search specific fields only
 def self.ransackable_attributes(auth_object = nil)
  %w[
    id
    crime_type
    crime_type_record_id
    officer_unit
    officer_name
    officer_bonid
    report_status
    report_id
    reviewed_by_id
    review_comment
    created_at
    submitted_at
    occurred_at
    description
    bonid_case_number
    qr_code
    officer_id
    department_id
    commune_id
  ]
end



def self.ransackable_associations(auth_object = nil)
  %w[officer department commune address]
end

# === Intelligence Methods ===
def intelligence
  @intelligence ||= IncidentIntelligenceService.new(self)
end

def calculated_severity
  intelligence.calculated_severity
end

def priority_score
  intelligence.priority_score
end

def find_related_incidents(limit: 10)
  intelligence.find_related_incidents(limit: limit)
end

def check_suspect_alerts
  intelligence.check_suspect_alerts
end

def suggest_crime_types(limit: 5)
  intelligence.suggest_crime_types(limit: limit)
end

# === Linking Methods ===
def link_to(other_report, link_type:, notes: nil, created_by: nil)
  IncidentLink.create_bidirectional(
    self, other_report,
    link_type: link_type,
    notes: notes,
    created_by: created_by
  )
end

def related_by_suspect
  linked_incidents.joins(:incident_links)
                  .where(incident_links: { link_type: "same_suspect" })
end

# === Review Workflow Methods ===
def current_review
  incident_reviews.order(created_at: :desc).first
end

def assign_reviewer(reviewer, assigned_by: nil, priority: 0, deadline_at: nil)
  incident_reviews.create!(
    reviewer: reviewer,
    assigned_by: assigned_by,
    priority: priority,
    deadline_at: deadline_at,
    assigned_at: Time.current,
    decision: :pending
  )
end

def approve!(reviewer:, summary: nil)
  transaction do
    update!(status: :approved)
    current_review&.update!(
      decision: :approved,
      completed_at: Time.current,
      summary: summary
    )
  end
end

def reject!(reviewer:, summary:)
  transaction do
    update!(status: :rejected)
    current_review&.update!(
      decision: :rejected,
      completed_at: Time.current,
      summary: summary
    )
  end
end

# === Report ID Generation (Using New Service) ===
def self.generate_scalable_report_id(crime_type:, officer:, occurred_at: nil)
  ReportIdGenerator.generate(
    crime_type: crime_type,
    officer: officer,
    occurred_at: occurred_at
  )
end



  # ── Anti-tamper: cryptographic report integrity ───────────────────────────
  #
  # HMAC-SHA256 over the five fields printed on every incident report:
  #   report_id | officer.badge_id | crime_type | occurred_at(ISO8601) | description[0..100]
  #
  # If ANY of those fields is altered in the DB the signature no longer matches
  # and `report_valid?` returns false — the public verify page shows ⚠ TAMPERED.

  # Compute and persist the HMAC signature immediately after creation.
  def sign_report!
    sig = compute_report_signature
    update_columns(report_signature: sig, report_signed_at: Time.current)
  rescue => e
    Rails.logger.error("[IncidentReport] sign_report! failed for #{report_id}: #{e.message}")
  end

  def compute_report_signature
    secret = Rails.application.credentials.dig(:bonid, :certificate_secret) ||
             Rails.application.credentials.secret_key_base
    payload = [
      report_id,
      officer&.badge_id.to_s.upcase,
      crime_type,
      occurred_at&.utc&.iso8601,
      description.to_s.first(100),
      signed_by_badge_id.to_s       # who attested — included in cryptographic proof
    ].join("|")
    OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
  end

  # Re-sign whenever a submitted report is edited so the HMAC reflects the new content.
  # Runs silently — if signing fails the update itself is not rolled back.
  def re_sign_if_submitted!
    return unless status_submitted?
    sign_report!
  end

  def report_valid?
    report_signature.present? &&
      ActiveSupport::SecurityUtils.secure_compare(
        report_signature,
        compute_report_signature
      )
  end

  # Short 8-char human-readable checksum printed on the report
  def report_checksum
    report_signature.to_s.first(8).upcase
  end

  # Public URL embedded in the QR code (judges/lawyers scan this, no login needed)
  def verify_url
    base = Rails.application.config.try(:bonid_verification_url) ||
           "https://verifie.pnh.gouv.ht"
    "#{base}/rapport/#{report_id}"
  end

  # Base64 PNG of the QR code pointing to verify_url (for integrity strip in show view)
  def report_qr_png_base64
    return @_report_qr if defined?(@_report_qr)
    @_report_qr = begin
      qr  = RQRCode::QRCode.new(verify_url, level: :h)
      png = qr.as_png(size: 180, border_modules: 2)
      Base64.strict_encode64(png.to_s)
    rescue => e
      Rails.logger.warn("[IncidentReport] QR generation failed for #{report_id}: #{e.message}")
      nil
    end
  end

  private

  def crime_code
    key = crime_type&.downcase&.gsub(/[^a-z\s]/, "")&.strip
    CRIME_CODES[key] || "UNKN"
  end

  # Inherit partner_id from the filing officer — required for access control scoping
  def set_partner_from_officer
    self.partner_id ||= officer&.partner_id
  end

  def set_submission_timestamp
    # Only stamp when the report is actually being submitted (not on draft saves)
    if status_submitted? || status_under_review? || status_approved?
      self.submitted_at ||= Time.current
    end
  end

  def set_officer_details
    return unless officer # Use the already associated officer

    self.officer_name ||= officer.full_name || "Unknown Officer"
    self.officer_bonid ||= Digest::SHA256.hexdigest(officer.badge_id || "NONE")[0..5].upcase
    self.officer_unit ||= officer.unit_type || "Unknown"
  end


  def generate_qr_code_and_case_number
    self.report_id ||= generate_report_id
    self.bonid_case_number ||= "BON-CASE-#{Time.current.year}-#{SecureRandom.hex(3).upcase}"
    # Point to official public verification domain so anyone scanning the QR
    # lands on verifie.pnh.gouv.ht rather than the internal bonid.ht URL
    verification_base = Rails.application.config.try(:bonid_verification_url) ||
                        "https://verifie.pnh.gouv.ht"
    url = "#{verification_base}/rapport/#{report_id}"
    qr  = RQRCode::QRCode.new(url)
    png = qr.as_png(size: 240)
    self.qr_code = Base64.strict_encode64(png.to_s)
  end

  def log_badge_id
    AuditLog.create!(
      record_type: "IncidentReport",
      record_id: id,
      officer_id: officer_id,
      badge_id: officer&.badge_id,
      action: "create",
      created_at: Time.current
    )
  end

  def notify_involved_citizens
    # Only notify victims, witnesses, and innocent parties
    # Suspects and accomplices should NOT be notified about investigations against them
    notifiable_roles = %w[victim witness innocent]

    person_involvements.where(role: notifiable_roles).each do |pi|
      NotifyCitizenJob.perform_later(pi.id) if pi.bonid.present?
    end
  end

  def validate_address_details
    return unless address
    unless address.commune_id.present? || address.street_address.present?
      errors.add(:address, "must include at least a commune or street address")
    end
  end

  def validate_person_involvements
    person_involvements.each do |pi|
      next if pi.marked_for_destruction?
      if pi.no_bonid
        errors.add(:base, "Persons without a BonID must have a name") if pi.name.blank?
        if pi.address&.commune_id.blank? && pi.address.present?
          errors.add(:base, "Persons without a BonID must have a valid address with a commune")
        end
      end
    end
  end

  def resolve_crime_type_record
    return if crime_type_record_id.present? || crime_type.blank?
    self.crime_type_record_id = CrimeType.find_by(name: crime_type)&.id
  end

  # Evidence file validation — 10 files max, 5MB each, images/videos only
  MAX_MEDIA_FILES = 10
  MAX_MEDIA_SIZE  = 5.megabytes
  ALLOWED_MEDIA_TYPES = %w[
    image/jpeg image/png image/webp image/heic image/heif
    video/mp4 video/quicktime video/webm
  ].freeze

  def validate_media_files
    return unless media.attached?

    if media.count > MAX_MEDIA_FILES
      errors.add(:media, "cannot exceed #{MAX_MEDIA_FILES} files (you have #{media.count})")
    end

    media.each do |file|
      if file.blob.byte_size > MAX_MEDIA_SIZE
        errors.add(:media, "#{file.filename} exceeds 5MB limit (#{(file.blob.byte_size / 1.megabyte.to_f).round(1)}MB)")
      end

      unless ALLOWED_MEDIA_TYPES.include?(file.blob.content_type)
        errors.add(:media, "#{file.filename} has unsupported type (#{file.blob.content_type})")
      end
    end
  end
end
