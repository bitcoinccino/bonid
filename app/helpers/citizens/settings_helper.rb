# frozen_string_literal: true

module Citizens
  module SettingsHelper
    # Returns "j***n@gmail.com" — first + last char of the local part,
    # asterisks in the middle, full domain. Short local parts (≤2 chars)
    # are fully starred.
    def mask_email(email)
      return "" if email.blank?

      local, domain = email.to_s.split("@", 2)
      return email if domain.blank?

      masked_local =
        if local.length <= 2
          "*" * local.length
        else
          "#{local[0]}#{'*' * [ local.length - 2, 3 ].min}#{local[-1]}"
        end

      "#{masked_local}@#{domain}"
    end

    # Mask the middle of a phone number — keeps the country code, the
    # next group (area code / carrier prefix), and the last 4 digits.
    # Preserves all separators / spaces / parens / + so e.g.
    #   "+509 37 12 3456"      → "+509 37 ** 3456"
    #   "+1 (954) 123-4567"    → "+1 (954) ***-4567"
    #   "5093712345" (no sep)  → "509***2345"  (falls back to CC + last 4)
    def mask_phone(phone)
      return "" if phone.blank?

      total_digits = phone.to_s.scan(/\d/).length
      return phone if total_digits < 5

      # Country-code-plus-area-code prefix when the number has a separator
      # between them; otherwise just the country code.
      prefix_digit_count =
        if (m = phone.to_s.match(/\A\+?(\d{1,3})[\s\-().]+(\d{1,3})/))
          m[1].length + m[2].length
        elsif (m = phone.to_s.match(/\A\+?(\d{1,3})/))
          m[1].length
        else
          0
        end

      trailing_keep = 4
      return phone if total_digits <= prefix_digit_count + trailing_keep

      seen = 0
      phone.to_s.gsub(/\d/) do |d|
        seen += 1
        if seen <= prefix_digit_count || seen > total_digits - trailing_keep
          d
        else
          "*"
        end
      end
    end
  end
end
