# frozen_string_literal: true

module CountryHelper
  def grouped_country_options
    grouped = ISO3166::Country.all.group_by { |c| region_label(c) }

    grouped.transform_values do |countries|
      countries.map do |c|
        name = c.translations["en"] || c.data["name"] || c.alpha2
        [ name, c.alpha2 ]
      end.sort_by(&:first)
    end
  end

  def nationality_options
    ISO3166::Country.all.map do |c|
      nationality = c.try(:nationality) || c.data["nationality"] || c.translations["en"] || c.alpha2
      [ nationality, nationality ]
    end.uniq.sort_by(&:first)
  end

  private

  def region_label(country)
    # Caribbean detection by ISO alpha2 code (covers all regional island nations)
    caribbean_codes = %w[
      HT DO JM TT BB BS LC GD KN VC DM AG
      CU PR VI KY TC AI GP MQ BL MF SX CW AW BQ
    ]

    return "🏝️ Caribbean" if caribbean_codes.include?(country.alpha2)

    case country.continent
    when "Africa" then "🌍 Africa"
    when "Asia" then "🌏 Asia"
    when "Europe" then "🌍 Europe"
    when "North America" then "🌎 North America (Non-Caribbean)"
    when "South America" then "🌎 South America"
    when "Oceania" then "🌊 Oceania"
    else "Other Regions"
    end
  end
end
