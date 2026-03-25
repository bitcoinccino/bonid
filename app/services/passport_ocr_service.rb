# frozen_string_literal: true

# app/services/passport_ocr_service.rb
#
# Extracts passport fields from a photo using AWS Textract.
# Uses analyze_document with FORMS feature type + MRZ line parsing.
#
# Usage:
#   result = PassportOcrService.call(image_bytes)
#   result[:success]  # => true/false
#   result[:fields]   # => { first_name:, last_name:, dob:, ... }
#
class PassportOcrService
  require "aws-sdk-textract"

  # MRZ field label mappings (case-insensitive)
  FIELD_MAPPINGS = {
    "surname"          => :last_name,
    "given name"       => :first_name,
    "given names"      => :first_name,
    "prénoms"          => :first_name,
    "nom"              => :last_name,
    "date of birth"    => :dob,
    "date de naissance" => :dob,
    "nationality"      => :nationality,
    "nationalité"      => :nationality,
    "passport no"      => :passport_number,
    "passport number"  => :passport_number,
    "numéro"           => :passport_number,
    "date of expiry"   => :passport_expiry_date,
    "expiry date"      => :passport_expiry_date,
    "date d'expiration" => :passport_expiry_date,
    "expiration"       => :passport_expiry_date,
    "sex"              => :sex,
    "sexe"             => :sex
  }.freeze

  attr_reader :image_bytes

  def initialize(image_bytes)
    @image_bytes = image_bytes
  end

  def self.call(image_bytes)
    new(image_bytes).call
  end

  def call
    response = self.class.textract_client.analyze_document(
      document: { bytes: image_bytes },
      feature_types: ["FORMS"]
    )

    fields = extract_form_fields(response)
    mrz_fields = extract_mrz_fields(response)

    # MRZ fields are more reliable — merge them over form fields
    merged = fields.merge(mrz_fields) { |_key, form_val, mrz_val| mrz_val.present? ? mrz_val : form_val }

    # Normalize extracted values
    normalize_fields!(merged)

    if merged.values.any?(&:present?)
      { success: true, fields: merged }
    else
      { success: false, error: "No passport fields detected in the image." }
    end
  rescue Aws::Textract::Errors::ServiceError => e
    Rails.logger.error "[PassportOcrService] AWS Textract error: #{e.class} - #{e.message}"
    { success: false, error: "Document analysis failed: #{e.message.truncate(200)}" }
  rescue StandardError => e
    Rails.logger.error "[PassportOcrService] Unexpected error: #{e.class} - #{e.message}"
    { success: false, error: "Unexpected error processing passport image." }
  end

  private

  # Extract key-value pairs from Textract FORMS response
  def extract_form_fields(response)
    fields = {
      first_name: nil, last_name: nil, dob: nil,
      nationality: nil, passport_number: nil,
      passport_expiry_date: nil, sex: nil
    }

    blocks = response.blocks
    key_map = {}
    value_map = {}
    block_map = {}

    blocks.each do |block|
      block_map[block.id] = block
      key_map[block.id] = block if block.block_type == "KEY_VALUE_SET" && block.entity_types&.include?("KEY")
      value_map[block.id] = block if block.block_type == "KEY_VALUE_SET" && block.entity_types&.include?("VALUE")
    end

    key_map.each_value do |key_block|
      key_text = get_text(key_block, block_map).strip.downcase

      # Find matching field
      field_key = FIELD_MAPPINGS[key_text]
      next unless field_key

      # Find associated value block
      value_block_id = key_block.relationships
        &.find { |r| r.type == "VALUE" }
        &.ids&.first
      next unless value_block_id

      value_block = block_map[value_block_id]
      next unless value_block

      value_text = get_text(value_block, block_map).strip
      fields[field_key] = value_text if value_text.present?
    end

    fields
  end

  # Extract text from a block by following CHILD relationships
  def get_text(block, block_map)
    return "" unless block.relationships

    child_rel = block.relationships.find { |r| r.type == "CHILD" }
    return "" unless child_rel

    child_rel.ids.map do |child_id|
      child_block = block_map[child_id]
      child_block&.text || ""
    end.join(" ")
  end

  # Parse MRZ lines (bottom two lines of passport) for higher accuracy
  def extract_mrz_fields(response)
    fields = {}

    # Collect all LINE blocks
    lines = response.blocks
      .select { |b| b.block_type == "LINE" }
      .map { |b| b.text&.strip }
      .compact

    # MRZ lines are 44 characters, start with P< (Type P passport)
    mrz_lines = lines.select { |l| l.length >= 42 && l.match?(/^P[A-Z<]/) }

    # Also check for the second MRZ line (starts with passport number)
    mrz_line2_candidates = lines.select { |l| l.length >= 42 && l.match?(/^[A-Z0-9<]{9}[0-9]/) }

    if mrz_lines.any?
      line1 = mrz_lines.first.gsub(/[^A-Z0-9<]/, "")
      parse_mrz_line1(line1, fields)
    end

    if mrz_line2_candidates.any?
      line2 = mrz_line2_candidates.first.gsub(/[^A-Z0-9<]/, "")
      parse_mrz_line2(line2, fields)
    end

    fields
  end

  # MRZ Line 1: P<UTONORMAN<<EDWINA<<<<<<<<<<<<<<<<<<<<<
  #              ^  ^^^  ^^^^^^^  ^^^^^^^^
  #              |  |    surname  given names
  #              |  issuing country
  #              type
  def parse_mrz_line1(line, fields)
    return unless line.length >= 10

    # Names start after country code (positions 5+)
    names_section = line[5..] || ""
    parts = names_section.split("<<", 2)

    if parts.length >= 2
      surname = parts[0].tr("<", " ").strip
      given = parts[1].tr("<", " ").strip
      fields[:last_name] = surname.titleize if surname.present?
      fields[:first_name] = given.titleize if given.present?
    end

    # Issuing country / nationality (positions 2-4)
    country_code = line[2..4]&.tr("<", "")
    fields[:nationality] = country_code if country_code.present? && country_code.length == 3
  end

  # MRZ Line 2: L898902C<3UTO6908061F9406236ZE184226B<<<<<14
  #              ^^^^^^^^^  ^^^^^^  ^^^^^^
  #              passport#  DOB     expiry
  def parse_mrz_line2(line, fields)
    return unless line.length >= 28

    # Passport number: positions 0-8
    passport_num = line[0..8]&.tr("<", "")&.strip
    fields[:passport_number] = passport_num if passport_num.present?

    # Date of birth: positions 13-18 (YYMMDD)
    dob_raw = line[13..18]
    if dob_raw&.match?(/^\d{6}$/)
      fields[:dob] = parse_mrz_date(dob_raw, birth: true)
    end

    # Sex: position 20
    sex_char = line[20]
    if sex_char == "F"
      fields[:sex] = "female"
    elsif sex_char == "M"
      fields[:sex] = "male"
    end

    # Expiry date: positions 21-26 (YYMMDD)
    expiry_raw = line[21..26]
    if expiry_raw&.match?(/^\d{6}$/)
      fields[:passport_expiry_date] = parse_mrz_date(expiry_raw, birth: false)
    end
  end

  # Convert YYMMDD to YYYY-MM-DD
  def parse_mrz_date(raw, birth: false)
    yy = raw[0..1].to_i
    mm = raw[2..3]
    dd = raw[4..5]

    # For birth dates: 00-30 = 2000s, 31-99 = 1900s
    # For expiry dates: always 20xx
    if birth
      year = yy > 30 ? 1900 + yy : 2000 + yy
    else
      year = 2000 + yy
    end

    "#{year}-#{mm}-#{dd}"
  end

  # Normalize field values
  def normalize_fields!(fields)
    # Titleize names
    %i[first_name last_name].each do |key|
      fields[key] = fields[key].titleize if fields[key].present? && fields[key] == fields[key].upcase
    end

    # Normalize sex
    if fields[:sex].present?
      sex = fields[:sex].downcase.strip
      fields[:sex] = case sex
                     when "m", "male" then "male"
                     when "f", "female" then "female"
                     else sex
                     end
    end

    # Normalize date formats (try to convert various formats to YYYY-MM-DD)
    %i[dob passport_expiry_date].each do |key|
      next unless fields[key].present?
      begin
        date = Date.parse(fields[key])
        fields[key] = date.iso8601
      rescue Date::Error
        # Leave as-is if unparseable
      end
    end

    # Uppercase passport number
    fields[:passport_number] = fields[:passport_number].upcase if fields[:passport_number].present?
  end

  # Thread-safe singleton AWS Textract client
  def self.textract_client
    @textract_client ||= begin
      client_options = {
        region: Rails.application.credentials.dig(:aws, :textract, :region) ||
                Rails.application.credentials.dig(:aws, :rekognition, :region) ||
                "us-east-1",
        access_key_id: Rails.application.credentials.dig(:aws, :textract, :access_key_id) ||
                       Rails.application.credentials.dig(:aws, :rekognition, :access_key_id),
        secret_access_key: Rails.application.credentials.dig(:aws, :textract, :secret_access_key) ||
                           Rails.application.credentials.dig(:aws, :rekognition, :secret_access_key),
        retry_limit: 3,
        retry_backoff: ->(c) { sleep(2**c.retries * 0.3) }
      }

      ca_bundle = resolve_ca_bundle
      if ca_bundle
        client_options[:ssl_ca_bundle] = ca_bundle
        Rails.logger.info "[PassportOcrService] Using CA bundle: #{ca_bundle}"
      end

      Aws::Textract::Client.new(client_options)
    end
  end

  def self.resolve_ca_bundle
    candidates = [
      ENV["SSL_CERT_FILE"],
      ENV["AWS_CA_BUNDLE"],
      "/opt/homebrew/etc/ca-certificates/cert.pem",
      "/opt/homebrew/etc/openssl@3/cert.pem",
      "/usr/local/etc/openssl@3/cert.pem",
      "/usr/local/etc/ca-certificates/cert.pem",
      "/etc/ssl/cert.pem",
      "/etc/ssl/certs/ca-certificates.crt"
    ].compact

    candidates.find { |path| File.exist?(path) }
  end
  private_class_method :resolve_ca_bundle
end
