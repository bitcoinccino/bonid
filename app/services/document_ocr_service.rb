# frozen_string_literal: true

# Extracts text from CIN/Passport images using Google Cloud Vision API,
# then parses structured fields (name, DOB, sex, CIN number, expiry).
#
# Usage:
#   result = DocumentOcrService.new(image_blob).extract
#   # => { raw_text: "...", fields: { last_name: "PARAISON", ... }, confidence: 0.97 }
#
class DocumentOcrService
  class OcrError < StandardError; end

  VISION_API_URL = "https://vision.googleapis.com/v1/images:annotate"

  def initialize(blob)
    @blob = blob
  end

  def extract
    base64_image = download_and_encode
    response = call_vision_api(base64_image)
    raw_text = parse_response(response)

    {
      raw_text: raw_text,
      fields: parse_cin_fields(raw_text),
      confidence: extract_confidence(response)
    }
  end

  # Cross-check OCR fields against user-provided data.
  # Returns a hash of { field_name => { ocr:, form:, match: } }
  def self.cross_check(ocr_fields, user_data)
    checks = {}

    {
      last_name:  user_data[:last_name],
      first_name: user_data[:first_name],
      dob:        user_data[:dob],
      sex:        user_data[:sex],
      document_number: user_data[:document_number]
    }.each do |field, form_value|
      ocr_value = ocr_fields[field]
      next if ocr_value.blank? && form_value.blank?

      match = if ocr_value.blank? || form_value.blank?
                false
              elsif field == :dob
                normalize_date(ocr_value) == normalize_date(form_value)
              else
                fuzzy_match?(ocr_value.to_s, form_value.to_s)
              end

      checks[field] = {
        ocr: ocr_value,
        form: form_value.to_s,
        match: match
      }
    end

    checks
  end

  private

  def download_and_encode
    Base64.strict_encode64(@blob.download)
  end

  def call_vision_api(base64_image)
    api_key = ENV["GOOGLE_VISION_API_KEY"]
    raise OcrError, "GOOGLE_VISION_API_KEY not set" if api_key.blank?

    conn = Faraday.new do |f|
      f.options.timeout = 15
      f.options.open_timeout = 5
    end

    response = conn.post("#{VISION_API_URL}?key=#{api_key}") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = {
        requests: [{
          image: { content: base64_image },
          features: [{ type: "TEXT_DETECTION", maxResults: 1 }]
        }]
      }.to_json
    end

    unless response.success?
      raise OcrError, "Vision API error (#{response.status}): #{response.body}"
    end

    JSON.parse(response.body)
  end

  def parse_response(response)
    annotations = response.dig("responses", 0, "textAnnotations")
    return "" if annotations.blank?

    annotations.first["description"] || ""
  end

  def extract_confidence(response)
    pages = response.dig("responses", 0, "fullTextAnnotation", "pages")
    return nil if pages.blank?

    confidences = pages.flat_map do |page|
      page["blocks"]&.map { |b| b["confidence"] } || []
    end.compact

    return nil if confidences.empty?
    (confidences.sum / confidences.size).round(4)
  end

  # Parse Haitian CIN fields from raw OCR text (French/Kreyòl)
  def parse_cin_fields(text)
    return {} if text.blank?

    fields = {}

    # Last name: "Nom:" or "NOM:" followed by value
    if (m = text.match(/Nom\s*[:;]\s*(.+)/i))
      fields[:last_name] = clean_field(m[1])
    end

    # First name: "Prénom:" or "Prenom:" or "PRENOM:"
    if (m = text.match(/Pr[ée]nom[s]?\s*[:;]\s*(.+)/i))
      fields[:first_name] = clean_field(m[1])
    end

    # Date of birth: "Né(e) le:" or "Date de naissance:" or "DN:"
    if (m = text.match(/(?:N[ée]\(?e?\)?\s*le|Date\s*de\s*naissance|DN)\s*[:;]?\s*([\d\-\/\.]+)/i))
      fields[:dob] = clean_field(m[1])
    end

    # Sex: "Sexe:" followed by M or F
    if (m = text.match(/Sexe\s*[:;]\s*([MF])/i))
      fields[:sex] = m[1].upcase
    end

    # Place of birth: "Lieu de naissance:" or "Lieu:"
    if (m = text.match(/Lieu\s*(?:de\s*naissance)?\s*[:;]\s*(.+)/i))
      fields[:place_of_birth] = clean_field(m[1])
    end

    # CIN Number: 10-digit NINU or 14/17-digit NIN
    # Look for standalone sequences of 10, 14, or 17 digits
    if (m = text.match(/\b(\d{10})\b/))
      fields[:document_number] = m[1] unless m[1].match?(/\d{11}/) # Not part of longer number
    elsif (m = text.match(/\b(\d{14})\b/))
      fields[:document_number] = m[1]
    elsif (m = text.match(/\b(\d{17})\b/))
      fields[:document_number] = m[1]
    end

    # Expiry date: "Date d'expiration:" or "Expire:" or "Exp:"
    if (m = text.match(/(?:Date\s*d['']?\s*expiration|Expire|Exp|Valable\s*jusqu)\s*[:;]?\s*([\d\-\/\.]+)/i))
      fields[:expiry_date] = clean_field(m[1])
    end

    # Department: "Département:" or just after commune
    if (m = text.match(/D[ée]partement\s*[:;]\s*(.+)/i))
      fields[:department] = clean_field(m[1])
    end

    # Commune
    if (m = text.match(/Commune\s*[:;]\s*(.+)/i))
      fields[:commune] = clean_field(m[1])
    end

    # Nationality
    if (m = text.match(/Nationalit[ée]\s*[:;]\s*(.+)/i))
      fields[:nationality] = clean_field(m[1])
    end

    fields
  end

  def clean_field(value)
    value.to_s.strip.split("\n").first&.strip&.gsub(/\s+/, " ")
  end

  def self.fuzzy_match?(a, b)
    return true if a.downcase.strip == b.downcase.strip

    # Levenshtein distance: allow 2 char difference for names
    distance = levenshtein(a.downcase.strip, b.downcase.strip)
    max_len = [a.length, b.length].max
    return true if max_len <= 3 && distance <= 1
    return true if max_len > 3 && distance <= 2

    # Also check if one contains the other (handles middle names)
    a.downcase.include?(b.downcase) || b.downcase.include?(a.downcase)
  end

  def self.levenshtein(s, t)
    m, n = s.length, t.length
    d = Array.new(m + 1) { |i| i }
    (1..n).each do |j|
      prev = d[0]
      d[0] = j
      (1..m).each do |i|
        temp = d[i]
        d[i] = if s[i - 1] == t[j - 1]
                 prev
               else
                 [prev, d[i], d[i - 1]].min + 1
               end
        prev = temp
      end
    end
    d[m]
  end

  def self.normalize_date(value)
    return value.iso8601 if value.is_a?(Date) || value.is_a?(Time)

    # Try common date formats: DD-MM-YYYY, DD/MM/YYYY, YYYY-MM-DD
    cleaned = value.to_s.strip
    if (m = cleaned.match(%r{\A(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\z}))
      "%04d-%02d-%02d" % [m[3].to_i, m[2].to_i, m[1].to_i]
    elsif (m = cleaned.match(%r{\A(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\z}))
      "%04d-%02d-%02d" % [m[1].to_i, m[2].to_i, m[3].to_i]
    else
      cleaned
    end
  end
end
