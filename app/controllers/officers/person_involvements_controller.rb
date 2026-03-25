module Officers
  class PersonInvolvementsController < ApplicationController
    before_action :authenticate_officer!

    def fetch_identity
      raw_input = params[:bonid]&.strip

      if raw_input.blank?
        return render json: { success: false, error: "Please enter a BonID or BonTouris" }
      end

      # Normalize input: remove dashes, handle lowercase, format properly
      normalized = normalize_bonid_input(raw_input)

      # Route to appropriate lookup based on normalized format
      if tourist_lookup?(normalized)
        return fetch_tourist_identity(normalized)
      end

      # Otherwise, handle as BonID (citizen) lookup
      fetch_citizen_identity(normalized)
    end

    private

    # Normalize user input to standard format
    # Supports: lowercase, no dashes, various formats
    # Examples:
    #   "8697XDS"      → "8697XDS"        (citizen suffix)
    #   "p8697XDS"     → "P8697XDS"       (citizen with P prefix)
    #   "DV1989P8697XDS" → "DV-1989-M-SE-P8697XDS" (full citizen)
    #   "123456"       → "123456"         (tourist - 6 digits)
    #   "p123456"      → "P-123456"       (tourist suffix)
    #   "t2024p123456" → "T-2024-P-123456" (full tourist)
    def normalize_bonid_input(raw)
      input = raw.strip.upcase
      clean = input.gsub("-", "")

      case clean
      when /^T(\d{4})P?(\d{6})$/ # Tourist full: T2024P123456
        "T-#{$1}-P-#{$2}"
      when /^P(\d{6})$/          # Tourist suffix with P: P123456
        "P-#{$1}"
      when /^(\d{6})$/           # Pure 6 digits = tourist passport suffix
        $1
      when /^D(\d{4})P?(\d{7})$/ # Citizen full: D2024P8697761
        digits = $2
        "D-#{$1}-P-#{digits[0..3]}-#{digits[4..]}"
      when /^(\d{7})$/           # Pure 7 digits = citizen suffix
        "#{$1[0..3]}-#{$1[4..]}"
      when /^P(\d{7})$/          # Citizen with P prefix: P8697761
        digits = $1
        "P-#{digits[0..3]}-#{digits[4..]}"
      else
        input # Return as-is if no pattern matches
      end
    end

    # Determine if the normalized input should trigger tourist lookup
    def tourist_lookup?(normalized)
      # Tourist patterns:
      # - Full BonTouris: T-YYYY-P-XXXXXX
      # - Passport suffix with P: P-XXXXXX
      # - Pure 6 digits (passport last 6)
      normalized.start_with?("T-") ||
        normalized.match?(/^P-\d{6}$/) ||
        normalized.match?(/^\d{6}$/)
    end

    # Lookup BonTouris (tourist) identity
    def fetch_tourist_identity(bonid)
      # Try exact match first
      visitor = VisitorSubmission.approved.find_by(bonid: bonid)

      # If not found, try flexible lookup (P-123456 format - passport suffix)
      if visitor.nil?
        # Extract digits from passport suffix format
        digits = bonid.gsub(/[^0-9]/, "")
        if digits.length == 6
          # Try matching last 6 digits of passport
          visitor = VisitorSubmission.approved.where("passport_number LIKE ?", "%#{digits}").first
          # Or try BonTouris with T- prefix
          visitor ||= VisitorSubmission.approved.where("bonid LIKE ?", "T-%-#{digits}%").first
        end
      end

      if visitor.nil?
        return render json: { success: false, error: "BonTouris not found. Verify passport digits." }
      end

      # Calculate stay status
      days_remaining = visitor.days_remaining
      stay_status = visitor.stay_status

      render json: {
        success: true,
        is_tourist: true,
        visitor_submission_id: visitor.id,
        bonid: visitor.bonid,
        first_name: visitor.first_name || "",
        middle_name: visitor.middle_name || "",
        last_name: visitor.last_name || "",
        sex: visitor.sex || "",
        nationality: visitor.nationality || "",
        date_of_birth: visitor.dob,
        passport_number: visitor.passport_number,
        phone: visitor.phone,
        email: visitor.email,
        photo_url: visitor.selfie.attached? ? url_for(visitor.selfie) : nil,
        # Stay status for tourists
        days_remaining: days_remaining,
        stay_status: stay_status,
        expires_at: visitor.expires_at,
        is_overstay: stay_status == :overstay,
        overstay_days: visitor.overstay_days
      }
    end

    # Lookup BonID (citizen) identity
    def fetch_citizen_identity(bonid)
      # Try to find by exact BonID first
      submission = IdentitySubmission.find_by(bonid: bonid)

      # If not found, try flexible suffix lookup
      # Supports with/without dashes: "8697-761", "8697761", "P8697-761", "P8697761", etc.
      if submission.nil?
        # Normalize: remove all dashes to get pure digits, then format with dash
        normalized = bonid.gsub("-", "")

        # Check if it's a suffix pattern (with or without letter prefix)
        if normalized.match?(/^[A-Z]?\d{6,7}$/i)
          # Extract letter prefix if present
          letter_prefix = normalized.match(/^([A-Z])/i)&.captures&.first&.upcase
          digits = normalized.gsub(/^[A-Z]/i, "")

          # Format as XXXX-XXX (4 digits, dash, 2-3 digits)
          if digits.length >= 6 && digits.length <= 7
            formatted_suffix = "#{digits[0..3]}-#{digits[4..]}"

            if letter_prefix
              # Try with letter prefix: P8697-761
              submission = IdentitySubmission.where("bonid LIKE ?", "%-#{letter_prefix}-#{formatted_suffix}").first
            end

            # Try without letter prefix or as fallback
            submission ||= IdentitySubmission.where("bonid LIKE ?", "%-P-#{formatted_suffix}").first
            submission ||= IdentitySubmission.where("bonid LIKE ?", "%-#{formatted_suffix}").first
            submission ||= IdentitySubmission.where("bonid LIKE ?", "%#{formatted_suffix}").first
          end
        end
      end

      if submission.nil?
        return render json: { success: false, error: "BonID not found in system" }
      end

      unless submission.status_approved?
        return render json: {
          success: false,
          error: "BonID is pending or rejected (status: #{submission.status&.humanize || 'unknown'})"
        }
      end

      user = submission.user
      unless user
        return render json: { success: false, error: "No user data linked to this BonID" }
      end

      # Check for ALL prior suspect/accomplice records
      prior_records = user.person_involvements
        .where(role: [:suspect, :accomplice])
        .where.not(status: nil)
        .includes(:incident_report)
        .order(created_at: :desc)
        .limit(10)

      render json: {
        success: true,
        is_tourist: false,
        no_bonid: false,
        user_id: user.id,
        bonid: submission.bonid,
        first_name: user.first_name || "",
        middle_name: user.middle_name || "",
        last_name: user.last_name || "",
        sex: user.sex || "",
        nationality: user.nationality || "Haitian",
        date_of_birth: user.dob,
        id_type: user.id_type,
        id_number: user.id_number,
        cin_unique_id: user.cin_unique_id,
        id_issued_on: user.id_issued_on,
        id_expires_on: user.id_expires_on,
        phone: user.phone,
        email: user.email,
        address: user.address&.full_address,
        photo_url: user.photo.attached? ? url_for(user.photo) : nil,
        place_of_birth_department_id: user.birth_department_id,
        place_of_birth_commune_id: user.birth_commune_id,
        # ALL prior suspect/accomplice records
        has_prior_records: prior_records.present?,
        prior_records_count: prior_records.count,
        prior_records: prior_records.map { |r|
          {
            role: r.role,
            role_display: r.role&.titleize,
            status: r.status,
            status_display: r.status&.titleize,
            incident_date: r.incident_report&.occurred_at,
            crime_type: r.incident_report&.crime_type&.humanize,
            severity_level: r.incident_report&.crime_severity_level,
            incident_id: r.incident_report&.id
          }
        }
      }
    end
  end
end
