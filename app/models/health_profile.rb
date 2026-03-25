class HealthProfile < ApplicationRecord
  belongs_to :user

  # === Constants ===
  BLOOD_TYPES_POSITIVE = %w[O+ A+ B+ AB+].freeze
  BLOOD_TYPES_NEGATIVE = %w[O- A- B- AB-].freeze
  BLOOD_TYPES = (BLOOD_TYPES_POSITIVE + BLOOD_TYPES_NEGATIVE).freeze

  # Common health data (localized to Haiti)
  COMMON_ALLERGIES = [
    "Peanuts", "Shellfish", "Pollen", "Dust", "Penicillin", "Latex",
    "Seafood", "Mold", "Insect Bites", "Other"
  ].freeze

  COMMON_CONDITIONS = [
    "Diabetes", "Hypertension", "Asthma", "Heart Disease", "Anemia",
    "Sickle Cell Disease", "HIV/AIDS", "Tuberculosis (TB)", "Malaria",
    "Typhoid Fever", "Dengue Fever", "Chronic Kidney Disease", "Epilepsy",
    "Gastritis", "Ulcers", "Migraine", "Other"
  ].freeze

  COMMON_MEDICATIONS = [
    "Metformin", "Lisinopril", "Aspirin", "Insulin", "Amoxicillin",
    "Ibuprofen", "Paracetamol", "Chloroquine", "Hydroxychloroquine",
    "Losartan", "Omeprazole", "Other"
  ].freeze

  validates :blood_type, inclusion: { in: BLOOD_TYPES }, allow_blank: true

  # === Virtual accessors for "Other" fields ===
  # These can be persisted later if you prefer via migration
  attr_accessor :allergies_other, :chronic_conditions_other, :medications_other

  # === Scalable field definitions ===
  FIELD_DEFINITIONS = {
    blood_type: {
      type: :select,
      label: "Blood Type",
      options: BLOOD_TYPES,
      placeholder: "Select your blood type",
      tooltip: "Choose your known blood type or leave blank if unknown."
    },
    allergies: {
      type: :multiselect,
      label: "Allergies",
      options: COMMON_ALLERGIES,
      placeholder: "Select allergies (if any)",
      tooltip: "Common allergies like peanuts or penicillin."
    },
    chronic_conditions: {
      type: :multiselect,
      label: "Chronic Conditions",
      options: COMMON_CONDITIONS,
      placeholder: "Select chronic or recurring conditions",
      tooltip: "Diseases or conditions you live with."
    },
    medications: {
      type: :multiselect,
      label: "Medications",
      options: COMMON_MEDICATIONS,
      placeholder: "Select or enter medications you take regularly",
      tooltip: "Common treatments or prescriptions."
    },
    organ_donor: {
      type: :boolean,
      label: "Organ Donor?",
      tooltip: "Would you donate organs in case of emergency?"
    }
  }.freeze

  # === Normalize array inputs ===
  def allergies=(value)
    super(normalize_input(value))
  end

  def chronic_conditions=(value)
    super(normalize_input(value))
  end

  def medications=(value)
    super(normalize_input(value))
  end

  # === Readers (return normalized lists) ===
  def allergies_list
    normalize_array(read_attribute(:allergies))
  end

  def chronic_conditions_list
    normalize_array(read_attribute(:chronic_conditions))
  end

  def medications_list
    normalize_array(read_attribute(:medications))
  end

  private

  def normalize_input(value)
    return [] if value.blank?

    result = if value.is_a?(String)
      value.strip.start_with?("[") ? normalize_array(value) : value.split(",").map(&:strip)
    elsif value.is_a?(Array)
      value
    else
      Array.wrap(value)
    end

    # Filter out blank/empty strings
    result.reject(&:blank?)
  end

  def normalize_array(value)
    return [] if value.blank?

    begin
      parsed = value.is_a?(String) ? JSON.parse(value) : value
      result = parsed.is_a?(Array) ? parsed : Array.wrap(parsed)
      # Filter out blank/empty strings
      result.reject(&:blank?)
    rescue JSON::ParserError
      Array.wrap(value).reject(&:blank?)
    end
  end
end
