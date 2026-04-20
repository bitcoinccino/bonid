# frozen_string_literal: true

module PartnerPortal
  # View helpers for the per-election diplomatic-mission CRUD.
  module DiplomaticMissionsHelper
    # Country-aware placeholder text for address-form inputs. Gives the
    # partner_admin a concrete example in the host country's local format
    # (e.g. ZIP "75008" for France vs "33130" for the US) so the UPU S42
    # formatter can render correctly downstream.
    PLACEHOLDERS = {
      "US" => { street: "1500 Brickell Ave, Suite 700", locality: "Miami",
                region: "FL", postal: "33129" },
      "CA" => { street: "1100 René-Lévesque Blvd W",  locality: "Montréal",
                region: "QC", postal: "H3B 4N4" },
      "FR" => { street: "10 Rue Théodule Ribot",      locality: "Paris",
                region: "",   postal: "75017" },
      "GF" => { street: "Lotissement Cogneau-Lamirande", locality: "Cayenne",
                region: "",   postal: "97300" },
      "GP" => { street: "30 Rue de l'Église",         locality: "Pointe-à-Pitre",
                region: "",   postal: "97110" },
      "DO" => { street: "Av. Juan Sánchez Ramírez 33", locality: "Santo Domingo",
                region: "",   postal: "10101" },
      "BR" => { street: "SHIS QI 9, Conjunto 8, Casa 9", locality: "Brasília",
                region: "DF", postal: "71625-080" },
      "BE" => { street: "Rue des Quatre Bras 26",     locality: "Bruxelles",
                region: "",   postal: "1000" },
      "DE" => { street: "Rheinbabenallee 14",         locality: "Berlin",
                region: "",   postal: "14199" },
      "ES" => { street: "Calle Marqués del Duero 3",  locality: "Madrid",
                region: "",   postal: "28001" },
      "GB" => { street: "Bute House, 5 Bute St",      locality: "London",
                region: "",   postal: "SW7 3EX" },
      "IT" => { street: "Via di Villa Patrizi 7",     locality: "Roma",
                region: "RM", postal: "00161" },
      "MX" => { street: "Sierra Gorda 510, Col. Lomas de Chapultepec",
                locality: "Ciudad de México", region: "CDMX", postal: "11000" },
      "AR" => { street: "Avenida Figueroa Alcorta 3297", locality: "Buenos Aires",
                region: "",   postal: "C1425CKB" },
      "BS" => { street: "East St & Soldier Rd",       locality: "Nassau",
                region: "",   postal: "" },
      "CL" => { street: "Av. Vitacura 4156",          locality: "Santiago",
                region: "",   postal: "7630412" },
      "CO" => { street: "Carrera 11 No 93-25 Of. 305", locality: "Bogotá",
                region: "",   postal: "110221" },
      "CU" => { street: "Calle 22 No 504 e/ 5ta y 7ma", locality: "La Habana",
                region: "",   postal: "11300" },
      "EC" => { street: "Av. 6 de Diciembre y Whymper", locality: "Quito",
                region: "",   postal: "170135" },
      "PA" => { street: "Calle 50, Edif. Plaza 50",   locality: "Ciudad de Panamá",
                region: "",   postal: "0832" },
      "SR" => { street: "Gravenstraat 23",            locality: "Paramaribo",
                region: "",   postal: "" },
      "VE" => { street: "Av. Francisco de Miranda",   locality: "Caracas",
                region: "",   postal: "1060" },
      "CW" => { street: "Schottegatweg Oost 11",      locality: "Willemstad",
                region: "",   postal: "" },
      "AW" => { street: "L.G. Smith Boulevard",       locality: "Oranjestad",
                region: "",   postal: "" },
      "TC" => { street: "Leeward Hwy",                locality: "Providenciales",
                region: "",   postal: "" },
      "JP" => { street: "1-3-13 Sanno Park Tower 4F", locality: "Tokyo",
                region: "Minato-ku", postal: "100-6104" },
      "QA" => { street: "West Bay, Diplomatic Area",  locality: "Doha",
                region: "",   postal: "" },
      "TW" => { street: "No. 333 Songjiang Rd",       locality: "Taipei",
                region: "",   postal: "104" },
      "VN" => { street: "Lotte Center, Lieu Giai",    locality: "Hanoi",
                region: "",   postal: "100000" },
      "VA" => { street: "Via della Conciliazione",    locality: "Città del Vaticano",
                region: "",   postal: "00120" },
      "ZA" => { street: "246 Carina Street",          locality: "Pretoria",
                region: "",   postal: "0181" },
      "CN" => { street: "3-1-72 Ta Yuan Diplomatic Compound", locality: "Beijing",
                region: "",   postal: "100600" }
    }.freeze

    def address_placeholder(country_code, field)
      PLACEHOLDERS.dig(country_code, field).presence || ""
    end

    # Returns the Unicode flag emoji for an ISO 3166-1 alpha-2 country code.
    # The flag is built from two regional indicator symbols (one per letter),
    # each derived by offsetting the uppercase ASCII letter into the U+1F1E6
    # block. This works on macOS / iOS / Android / modern Linux; Windows
    # platforms render a literal 2-letter code (e.g. "ZA") instead, which is
    # an acceptable graceful fallback for our use case.
    #
    #   country_flag("HT") # => "🇭🇹"
    #   country_flag("US") # => "🇺🇸"
    #   country_flag(nil)  # => ""
    def country_flag(code)
      return "" if code.blank?
      cc = code.to_s.upcase
      return "" unless cc.match?(/\A[A-Z]{2}\z/)
      cc.each_char.map { |c| (c.ord + 0x1F1A5).chr(Encoding::UTF_8) }.join
    end
  end
end
