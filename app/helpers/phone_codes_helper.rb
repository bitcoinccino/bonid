module PhoneCodesHelper
  def phone_country_code_options
    ISO3166::Country.all
      .select { |c| c.country_code.present? }
      .map do |country|
        name = country.translations[I18n.locale.to_s] || country.name
        code = "+#{country.country_code}"
        [ "#{name} (#{code})", code ]
      end
      .sort_by { |label, _| label }
  end

  # Country picker for the phone-with-country combo input. Each option's
  # value is the ISO2 (so it round-trips to a country lookup) and its
  # `data-dial-code` exposes the +NNN prefix to the Stimulus controller.
  #
  # Returns an Array of [label, iso2, html_options] suitable for
  # `options_for_select` (raw). Labels show ONLY the dial code and the
  # regional-indicator flag emoji ("+509 🇭🇹") — the country name is
  # carried on the option as `data-country-name` for accessibility /
  # future filtering, but isn't visible in the closed selectbox.
  # Sorted alphabetically by country name so the open dropdown stays
  # browsable even though the names aren't rendered.
  def phone_country_picker_options(selected_iso2 = nil)
    ISO3166::Country.all
      .select { |c| c.country_code.present? }
      .map do |country|
        iso2 = country.alpha2
        name = country.translations[I18n.locale.to_s] || country.iso_short_name
        flag = country_flag_emoji(iso2)
        [ "+#{country.country_code} #{flag}", iso2,
         { "data-dial-code"    => country.country_code,
           "data-country-name" => name,
           "title"             => "#{name} (+#{country.country_code})" } ]
      end
      .sort_by { |_label, _iso2, opts| opts["data-country-name"].to_s }
  end

  # Returns the +NNN dial code (no plus) for an ISO 3166-1 alpha-2 code.
  #   phone_dial_code("HT") # => "509"
  #   phone_dial_code(nil)  # => nil
  def phone_dial_code(iso2)
    return nil if iso2.blank?
    ISO3166::Country.new(iso2.to_s.upcase)&.country_code
  end

  # Regional-indicator flag emoji for an ISO2 code (matches the
  # PartnerPortal::DiplomaticMissionsHelper#country_flag implementation).
  def country_flag_emoji(code)
    return "" if code.blank?
    cc = code.to_s.upcase
    return "" unless cc.match?(/\A[A-Z]{2}\z/)
    cc.each_char.map { |c| (c.ord + 0x1F1A5).chr(Encoding::UTF_8) }.join
  end
end
