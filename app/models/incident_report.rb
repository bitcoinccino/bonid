# app/models/incident_report.rb
require "rqrcode"
require "base64"
require "csv"

class IncidentReport < ApplicationRecord
  belongs_to :officer
  belongs_to :address
  belongs_to :reviewed_by, class_name: "AdminUser", optional: true

  accepts_nested_attributes_for :address
  has_many_attached :media, dependent: :destroy

  enum :status, { pending: 0, approved: 1, flagged: 2 }

  # === Validations ===
  validates :report_id, :crime_type, :occurred_at, :description,
            :officer_name, :officer_bonid, :officer_unit,
            :address, :submitted_at, presence: true

  # === Callbacks ===
  before_validation :generate_report_id, on: :create
  before_create :set_submission_timestamp
  before_create :generate_qr_code_and_case_number
  belongs_to :suspect_user, class_name: "User", optional: true


  # app/models/incident_report.rb
enum :suspect_status, {
  in_custody: "In Custody",
  fugitive: "Fugitive",
  identity_unknown: "Identity Unknown",
  detained_awaiting_charges: "Detained Awaiting Charges",
  escaped_custody: "Escaped Custody",
  known_location: "Known Location",
  deceased: "Deceased",
  released_on_bail: "Released on Bail",
  under_surveillance: "Under Surveillance",
  transferred: "Transferred",
  awaiting_trial: "Awaiting Trial",
  convicted: "Convicted",
  acquitted: "Acquitted"
}



  # === CRIME TYPES ===
  CRIME_TYPES = {
    violent_crimes: ["Homicide", "Sexual Violence", "Kidnapping", "Assault", "Torture", "Lynching", "Police Brutality", "Domestic Violence", "Child Abduction", "Hate Crimes", "Gang Violence", "Mutilation", "Armed Assault", "Human Sacrifice", "Stalking", "Mass Murder", "Serial Killing", "Ethnic Cleansing"],
    property_crimes: ["Armed Robbery", "Burglary", "Theft", "Carjacking", "Home Invasion", "Vandalism", "Arson", "Larceny", "Shoplifting", "Fencing Stolen Goods", "Art Theft", "Livestock Theft"],
    organized_crime: ["Drug Trafficking", "Human Trafficking", "Arms Trafficking", "Organized Crime", "Racketeering", "Extortion", "Money Laundering", "Piracy", "Contract Killing", "Illegal Betting Syndicates", "Protection Rackets", "Organ Harvesting", "Cyber Extortion", "Sex Trafficking", "Labor Trafficking", "Child Trafficking", "Forced Marriage Trafficking", "Debt Bondage Trafficking", "Nuclear Material Trafficking", "Chemical Weapons Trafficking"],
    economic_crimes: ["Financial Fraud", "Embezzlement", "Corruption", "Counterfeiting", "Identity Theft", "Illegal Gambling", "Tax Evasion", "Bribery", "Ponzi Schemes", "Insider Trading", "Corporate Espionage", "Price Fixing", "Workplace Bribery", "Nepotism", "Cronyism", "Kickback Schemes", "Falsified Expense Reports", "Abuse of Authority"],
    smuggling_and_trafficking: ["Fuel Smuggling", "Smuggling of Goods", "Wildlife Trafficking", "Blackmail", "Antiquities Smuggling", "Tobacco Smuggling", "Pharmaceutical Trafficking", "Human Organ Trafficking", "Exotic Pet Trafficking"],
    social_and_emerging_crimes: ["Child Exploitation", "Forced Displacement", "Environmental Crime", "Election-Related Violence", "Prison Breaks", "Cybercrime", "Public Disorder", "Terrorism", "Land Disputes", "Revenge Pornography", "Online Harassment", "Deepfake Fraud", "Cryptocurrency Scams", "Food Contamination", "Vigilantism", "Bioterrorism", "Cyberterrorism", "Ecocide", "Illegal Protest Assembly", "Protest Incitement", "Protest-Related Arson", "Protest-Related Assault", "Barricade Destruction"],
    traffic_and_minor_infractions: ["Traffic Violation", "Driving Without License", "Vehicle Registration Violation", "Public Nuisance", "Littering", "Trespassing", "Minor Vandalism", "Disorderly Conduct", "Jaywalking", "Illegal Parking", "Noise Violations", "Public Intoxication", "Loitering", "Petty Theft"],
    political_and_state_crimes: ["Treason", "Espionage", "Sedition", "Election Tampering", "State-Sanctioned Violence", "Propaganda Dissemination", "Coup d'État", "War Crimes", "Genocide", "Crimes Against Humanity", "State-Sponsored Terrorism", "Protest-Driven Sedition", "Anti-Government Protest Conspiracy"],
    public_health_and_safety_crimes: ["Illegal Drug Manufacturing", "Food Adulteration", "Public Health Violations", "Hazardous Waste Dumping", "Unlicensed Medical Practice", "Quarantine Violations", "Vaccine Fraud", "Biological Weapons Use"],
    technology_and_data_crimes: ["Data Breaches", "Hacking", "Phishing", "Ransomware Attacks", "Dark Web Trafficking", "Software Piracy", "AI Manipulation", "Digital Forgery", "Critical Infrastructure Hacking"],
    intellectual_property_crimes: ["Copyright Infringement", "Trademark Counterfeiting", "Patent Infringement", "Trade Secret Theft", "Counterfeit Goods Distribution", "Digital Piracy", "Brand Impersonation", "Design Right Violation", "Music Copyright Infringement", "Unauthorized Music Streaming", "Music Plagiarism", "Bootleg Recordings"],
    prison_crimes: ["Inmate Homicide", "Prison Assault", "Contraband Smuggling in Prison", "Prison Guard Corruption", "Inmate Extortion", "Prison Gang Activity", "Sexual Exploitation in Prison", "Escape Conspiracy"]
  }.freeze

  # === CSV Export ===
  def self.to_csv
    attributes = %w[
      report_id crime_type occurred_at description officer_name officer_bonid
      suspect_name suspect_bonid suspect_status
      bonid_case_number submitted_at created_at
    ]

    CSV.generate(headers: true) do |csv|
      csv << attributes
      all.each do |report|
        csv << attributes.map { |attr| report.send(attr) }
      end
    end
  end

  private

  def generate_qr_code_and_case_number
    self.report_id ||= "CR-#{Time.now.year}-#{SecureRandom.hex(4).upcase}"
    self.submitted_at ||= Time.current
    self.bonid_case_number ||= "BON-CASE-#{Time.now.year}-#{SecureRandom.hex(3).upcase}"

    url = "https://bonid.ht/reports/#{report_id}"
    qrcode = RQRCode::QRCode.new(url)
    png = qrcode.as_png(size: 240)
    self.qr_code = Base64.encode64(png.to_s)
  end
end




