# frozen_string_literal: true

module PartnerPortal
  # View helpers for the polling-center create/edit wizard.
  #
  # Owns the JSON shape consumed by polling_center_type_controller.js
  # (mission registry + country names + flag emoji map) and the small
  # bits of country naming the country <select> needs.
  module PollingCentersHelper
    # Country names in Kreyòl/French where the diaspora community uses
    # them. Falls back to the ISO code if a country isn't listed here.
    COUNTRY_NAMES_FOR_WIZARD = {
      "US" => "Etazini",
      "CA" => "Kanada",
      "FR" => "Frans",
      "BE" => "Bèljik",
      "DE" => "Almay",
      "ES" => "Espay",
      "GB" => "Wayòm Ini",
      "IT" => "Itali",
      "VA" => "Vatikan",
      "BR" => "Brezil",
      "AR" => "Ajantin",
      "CL" => "Chili",
      "CO" => "Kolonbi",
      "EC" => "Ekwatè",
      "MX" => "Meksik",
      "PA" => "Panama",
      "VE" => "Venezuela",
      "SR" => "Sirinam",
      "DO" => "Repiblik Dominikèn",
      "BS" => "Bahamas",
      "CU" => "Kiba",
      "CW" => "Kiraso",
      "AW" => "Awouba",
      "TC" => "Turks ak Caïques",
      "GF" => "Giyàn Franse",
      "GP" => "Gwadloup",
      "JP" => "Japon",
      "QA" => "Katar",
      "TW" => "Taywann",
      "VN" => "Vyetnam",
      "ZA" => "Afrik di Sid",
      "CN" => "Lachin"
    }.freeze

    # Returns the flat mission registry as a JSON-ready Array of Hashes.
    # Shape per entry mirrors what the Stimulus controller's autofill
    # logic looks up by `data-autofill-key`.
    def polling_center_wizard_missions_json
      HaitianDiplomaticMissions::ALL_MISSIONS.map do |m|
        {
          id:           m[:id],
          name:         m[:name],
          type:         m[:type],
          country:      m[:country],
          street_line1: m.dig(:address, :street_line1),
          street_line2: m.dig(:address, :street_line2),
          locality:     m.dig(:address, :locality),
          region:       m.dig(:address, :region),
          postal_code:  m.dig(:address, :postal_code),
          phone:        m.dig(:contact, :phone),
          email:        m.dig(:contact, :email)
        }
      end
    end

    # Map of ISO code → display name, scoped to countries that actually
    # host a Haitian mission. Sorted alphabetically by display name so
    # the country <select> reads naturally.
    def polling_center_wizard_country_names
      mission_countries = HaitianDiplomaticMissions::ALL_MISSIONS.map { |m| m[:country] }.uniq
      mission_countries.each_with_object({}) do |cc, h|
        h[cc] = COUNTRY_NAMES_FOR_WIZARD[cc] || cc
      end
    end

    # Map of ISO code → 2-glyph flag emoji, same key set as country names.
    # Reuses the flag builder defined in DiplomaticMissionsHelper.
    def polling_center_wizard_country_flags
      polling_center_wizard_country_names.keys.each_with_object({}) do |cc, h|
        h[cc] = country_flag(cc)
      end
    end

    # Returns options for the country <select>, sorted alphabetically
    # by Kreyòl name, with the flag prepended for visual scanning.
    def polling_center_wizard_country_options
      polling_center_wizard_country_names
        .sort_by { |_cc, name| name }
        .map { |cc, name| [ "#{country_flag(cc)} #{name}", cc ] }
    end
  end
end
