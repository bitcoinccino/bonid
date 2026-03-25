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
end
