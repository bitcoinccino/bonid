# frozen_string_literal: true

# Haiti's diplomatic missions worldwide — used by election system
# for consulate voting stations and diaspora channel mapping.
#
# Source: Wikipedia — Diplomatic missions of Haiti
# Updated: 2026-03-27
module HaitianDiplomaticMissions
  extend ActiveSupport::Concern

  # ── UNITED STATES ──────────────────────────────────────────────
  # Postal addresses + contact verified against ≥2 independent sources
  # (consulate official sites where reachable, haiti.org consular listing,
  # embassies.info, embassypages.com, IOM migrantinfo.iom.int, Wikipedia
  # Embassy of Haiti article). Fields left nil have a `# unverified — …`
  # comment explaining why. Coordinates uniformly nil pending a separate
  # geocoding pass; the source aggregators don't carry decimal-precision
  # lat/lng. Top-level `region:` is the GEOGRAPHIC region used for
  # grouping; postal state code lives under `address[:region]`.
  US_MISSIONS = [
    {
      id: "HT-EMB-WAS", name: "Washington, D.C.", type: "embassy",
      country: "US", region: "north_america",
      address: {
        street_line1: "2311 Massachusetts Ave NW",
        street_line2: nil,
        locality: "Washington",
        region: "DC",
        postal_code: "20008",
        latitude: nil,  # unverified — no decimal-precision source
        longitude: nil
      },
      contact: {
        phone: "+1 202-332-4090",
        email: "amb.washington@diplomatie.ht"  # confirmed by founder-provided directory
      }
    },
    {
      id: "HT-CON-ATL", name: "Atlanta, GA", type: "consulate_general",
      country: "US", region: "north_america",
      address: {
        street_line1: "2911 Piedmont Rd NE",
        street_line2: "Suite F",  # confirmed by founder-provided directory (resolves earlier F vs A conflict)
        locality: "Atlanta",
        region: "GA",
        postal_code: "30305",
        latitude: nil,
        longitude: nil
      },
      contact: {
        phone: "+1 404-228-5373",
        email: "cg.atlanta@diplomatie.ht"
      }
    },
    {
      id: "HT-CON-BOS", name: "Boston, MA", type: "consulate_general",
      country: "US", region: "north_america",
      address: {
        street_line1: "333 Washington St",
        street_line2: "Suite 851",
        locality: "Boston",
        region: "MA",
        postal_code: "02108",
        latitude: nil,
        longitude: nil
      },
      contact: {
        phone: "+1 857-449-0332",  # confirmed by founder-provided directory (617-266-3660 also appears as alt line)
        email: "cg.boston@diplomatie.ht"
      }
    },
    {
      id: "HT-CON-CHI", name: "Chicago, IL", type: "consulate_general",
      country: "US", region: "north_america",
      address: {
        street_line1: "11 East Adams St",
        street_line2: "Suite 1500",
        locality: "Chicago",
        region: "IL",
        postal_code: "60603",
        latitude: nil,
        longitude: nil
      },
      contact: {
        phone: "+1 872-710-4141",
        email: "info@haitianconsulatechicago.com"  # founder-provided; cg.chicago@diplomatie.ht is the alt diplomatie.ht alias
      }
    },
    {
      id: "HT-CON-MIA", name: "Miami, FL", type: "consulate_general",
      country: "US", region: "north_america",
      address: {
        street_line1: "259 SW 13th St",
        street_line2: "Suite 3",
        locality: "Miami",
        region: "FL",
        postal_code: "33130",
        latitude: nil,
        longitude: nil
      },
      contact: {
        phone: "+1 305-859-2003",
        email: "cg.miami@diplomatie.ht"
      }
    },
    {
      id: "HT-CON-NYC", name: "New York, NY", type: "consulate_general",
      country: "US", region: "north_america",
      address: {
        # Founder-provided directory: 555 5th Ave, 3rd Floor, NY 10017.
        # Earlier WebFetch verification found 815 Second Ave, 6th Floor on
        # cghaitiny.org and several aggregators — likely the prior address.
        # Going with founder's value as authoritative; revert if 555 5th Ave
        # turns out to be incorrect.
        street_line1: "555 5th Ave",
        street_line2: "3rd Floor",
        locality: "New York",
        region: "NY",
        postal_code: "10017",
        latitude: nil,
        longitude: nil
      },
      contact: {
        phone: "+1 212-697-9767",
        email: "cg.newyork@diplomatie.ht"
      }
    },
    {
      id: "HT-CON-ORL", name: "Orlando, FL", type: "consulate_general",
      country: "US", region: "north_america",
      address: {
        street_line1: "1616 E Colonial Dr",
        street_line2: nil,  # not_found — no suite listed in any public source
        locality: "Orlando",
        region: "FL",
        postal_code: "32803",
        latitude: nil,
        longitude: nil
      },
      contact: {
        phone: "+1 407-897-1262",  # primary; (407) 897-3232 / (689) 258-7993 listed as alternates in some sources
        email: "cons.orlando@diplomatie.ht"
      }
    }
  ].freeze

  # ── DOMINICAN REPUBLIC ─────────────────────────────────────────
  # Addresses + phones from founder-provided directory. Postal codes and
  # emails not in the source — left nil. DR addresses commonly omit postal
  # codes in practice; the formatter handles a missing postal cleanly.
  DR_MISSIONS = [
    {
      id: "HT-EMB-SDQ", name: "Santo Domingo", type: "embassy",
      country: "DO", region: "caribbean",
      address: {
        street_line1: "Ave. Juan Sánchez Ramírez 33",
        street_line2: "Gazcue",
        locality: "Santo Domingo",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 809-686-7115", email: nil }
    },
    {
      id: "HT-CON-BAR", name: "Barahona", type: "consulate_general",
      country: "DO", region: "caribbean",
      address: {
        street_line1: "Calle Carlos Nassis No. 8",
        street_line2: nil,
        locality: "Barahona",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 809-524-7353", email: nil }
    },
    {
      id: "HT-CON-DAJ", name: "Dajabón", type: "consulate_general",
      country: "DO", region: "caribbean",
      address: {
        street_line1: "Calle Beller",
        street_line2: nil,
        locality: "Dajabón",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 809-579-8287", email: nil }
    },
    {
      id: "HT-CON-HIG", name: "Higüey", type: "consulate_general",
      country: "DO", region: "caribbean",
      address: {
        street_line1: "C/ Gaston F. Deligne No. 50",
        street_line2: nil,
        locality: "Higüey",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 809-746-0781", email: nil }
    },
    {
      id: "HT-CON-STI", name: "Santiago de los Caballeros", type: "consulate_general",
      country: "DO", region: "caribbean",
      address: {
        street_line1: "Ave. Estrella Sadhalá #6",
        street_line2: nil,
        locality: "Santiago de los Caballeros",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 809-504-0651", email: nil }
    }
  ].freeze

  # ── OTHER AMERICAS ─────────────────────────────────────────────
  # 7 of 13 populated from founder-provided directory (Ottawa, Montréal,
  # Buenos Aires, Brasília, Mexico City, Panama City, Nassau). 6 still
  # nil — Santiago de Chile, Bogotá, La Havane, Quito, Paramaribo,
  # Caracas — pending future verification batch.
  AMERICAS_MISSIONS = [
    {
      id: "HT-EMB-BUE", name: "Buenos Aires", type: "embassy",
      country: "AR", region: "south_america",
      address: {
        street_line1: "Av. Figueroa Alcorta 3297",
        street_line2: nil,
        locality: "Buenos Aires",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+54 11 4802-5979", email: nil }
    },
    {
      id: "HT-EMB-NAS", name: "Nassau", type: "embassy",
      country: "BS", region: "caribbean",
      address: {
        street_line1: "Sears Hill Rd",
        street_line2: nil,
        locality: "Nassau",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 242-326-0325", email: nil }
    },
    {
      id: "HT-EMB-BSB", name: "Brasília", type: "embassy",
      country: "BR", region: "south_america",
      address: {
        street_line1: "SHIS QL 10 Conjunto 8 Casa 1",
        street_line2: nil,
        locality: "Brasília",
        region: "DF",
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+55 61 3248-6860", email: nil }
    },
    {
      id: "HT-EMB-OTT", name: "Ottawa", type: "embassy",
      country: "CA", region: "north_america",
      address: {
        street_line1: "85 Albert St",
        street_line2: "Suite 1110",
        locality: "Ottawa",
        region: "ON",
        postal_code: "K1P 6A4",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 613-238-1628", email: nil }
    },
    {
      id: "HT-CON-MTL", name: "Montréal, QC", type: "consulate_general",
      country: "CA", region: "north_america",
      address: {
        street_line1: "300 Rue Léo Pariseau",
        street_line2: "Suite 1100",
        locality: "Montréal",
        region: "QC",
        postal_code: "H2X 4C1",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 514-499-1919", email: nil }
    },
    {
      id: "HT-EMB-SCL", name: "Santiago de Chile", type: "embassy",
      country: "CL", region: "south_america",
      address: {
        street_line1: "Luz 2889",
        street_line2: "Of. 81",
        locality: "Las Condes",
        region: nil,
        postal_code: "7550033",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+56 2 2231 6794", email: nil }
    },
    {
      id: "HT-EMB-BOG", name: "Bogotá", type: "embassy",
      country: "CO", region: "south_america",
      address: {
        street_line1: "Cra. 12 # 70A - 36",
        street_line2: "Barrio Quinta Camacho",
        locality: "Bogotá",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+57 1 520 7729", email: nil }
    },
    {
      id: "HT-EMB-HAV", name: "La Havane", type: "embassy",
      country: "CU", region: "caribbean",
      address: {
        street_line1: "Calle 7ma. No. 4402",
        street_line2: "esq. a 44, Miramar",
        locality: "La Habana",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+53 7 204 5421", email: nil }
    },
    {
      id: "HT-EMB-UIO", name: "Quito", type: "embassy",
      country: "EC", region: "south_america",
      address: {
        street_line1: "Calle El Batán N34-67 y Eloy Alfaro",
        street_line2: nil,
        locality: "Quito",
        region: nil,
        postal_code: "170135",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+593 2 226 6777", email: nil }
    },
    {
      id: "HT-EMB-MEX", name: "Mexico City", type: "embassy",
      country: "MX", region: "north_america",
      address: {
        street_line1: "Sierra Vertientes 840",
        street_line2: "Lomas de Chapultepec",
        locality: "Ciudad de México",
        region: "CDMX",
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+52 55 5557-2065", email: nil }
    },
    {
      id: "HT-EMB-PTY", name: "Panama City", type: "embassy",
      country: "PA", region: "central_america",
      address: {
        street_line1: "Edif. World Trade Center",
        street_line2: "Calle 53 Este",
        locality: "Ciudad de Panamá",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+507 269-3443", email: nil }
    },
    {
      id: "HT-CON-PBM", name: "Paramaribo", type: "consulate_general",
      country: "SR", region: "south_america",
      address: {
        street_line1: "Mr. F.H.R. Lim A Po Straat 21",
        street_line2: nil,
        locality: "Paramaribo",
        region: nil,
        postal_code: nil,            # Suriname has no postal-code system
        latitude: nil, longitude: nil
      },
      contact: { phone: "+597 729 2000", email: nil }
    },
    {
      id: "HT-EMB-CCS", name: "Caracas", type: "embassy",
      country: "VE", region: "south_america",
      address: {
        street_line1: "Quinta San Rafael",
        street_line2: "Avenida Transversal 8",
        locality: "Caracas",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+58 212 262 1194", email: nil }
    }
  ].freeze

  # ── EUROPE & OTHER ─────────────────────────────────────────────
  # All 19 entries populated from founder-provided directory (final batch
  # added Paris consulate, Cayenne, Pointe-à-Pitre, Willemstad,
  # Turks & Caicos, Doha, plus 2 new entries: Pretoria (ZA) and
  # Beijing (CN) — these last two were not in the original 42-mission
  # list; they bring the total to 44 missions.
  EUROPE_OTHER_MISSIONS = [
    {
      id: "HT-EMB-BRU", name: "Bruxelles", type: "embassy",
      country: "BE", region: "europe",
      address: {
        street_line1: "Chaussée de Charleroi 139",
        street_line2: nil,
        locality: "Bruxelles",
        region: nil,
        postal_code: "1060",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+32 2 649 73 81", email: nil }
    },
    {
      id: "HT-EMB-PAR", name: "Paris", type: "embassy",
      country: "FR", region: "europe",
      address: {
        street_line1: "10 Rue Théodule Ribot",
        street_line2: nil,
        locality: "Paris",
        region: nil,
        postal_code: "75017",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+33 1 47 63 47 78", email: nil }
    },
    {
      id: "HT-CON-PAR", name: "Paris (Consulat)", type: "consulate_general",
      country: "FR", region: "europe",
      address: {
        street_line1: "35 Avenue de Villiers",
        street_line2: nil,
        locality: "Paris",
        region: nil,
        postal_code: "75017",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+33 1 42 12 70 50", email: nil }
    },
    {
      id: "HT-CON-CAY", name: "Cayenne, Guyane", type: "consulate_general",
      country: "GF", region: "south_america",
      address: {
        street_line1: "12 Avenue Léopold Héder",
        street_line2: nil,
        locality: "Cayenne",
        region: nil,
        postal_code: "97300",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+594 594 31 18 58", email: nil }
    },
    {
      id: "HT-CON-PTP", name: "Pointe-à-Pitre, Guadeloupe", type: "consulate",
      country: "GP", region: "caribbean",
      address: {
        street_line1: "12 Rue Schoelcher",
        street_line2: nil,
        locality: "Pointe-à-Pitre",
        region: nil,
        postal_code: "97110",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+590 590 89 35 80", email: nil }
    },
    {
      id: "HT-EMB-BER", name: "Berlin", type: "embassy",
      country: "DE", region: "europe",
      address: {
        street_line1: "Uhlandstraße 14",
        street_line2: nil,
        locality: "Berlin",
        region: nil,
        postal_code: "10623",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+49 30 88 55 41 34", email: nil }
    },
    {
      id: "HT-EMB-ROM", name: "Rome (Saint-Siège)", type: "embassy",
      country: "VA", region: "europe",
      address: {
        # Note: postal code 00136 is the Italian (Rome) postcode where the
        # mission is physically located. Vatican City's own postcode is
        # 00120 — not used here because the mission isn't inside the city
        # walls. Phone matches the Italy mission's switchboard per
        # founder-provided directory; flagged in case it's a duplicate.
        street_line1: "Via dell'Erta Canina 3",
        street_line2: nil,
        locality: "Roma",
        region: nil,
        postal_code: "00136",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+39 06 44 25 41 06", email: nil }
    },
    {
      id: "HT-EMB-ROM2", name: "Rome (Italie)", type: "embassy",
      country: "IT", region: "europe",
      address: {
        street_line1: "Via Di Villa Patrizi 7",
        street_line2: nil,
        locality: "Roma",
        region: "RM",
        postal_code: "00161",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+39 06 44 25 41 06", email: nil }
    },
    {
      id: "HT-CON-WIL", name: "Willemstad, Curaçao", type: "consulate_general",
      country: "CW", region: "caribbean",
      address: {
        street_line1: "Grebbelinweg 18",
        street_line2: nil,
        locality: "Willemstad",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+599 9 461 3434", email: nil }
    },
    {
      id: "HT-CON-ORA", name: "Oranjestad, Aruba", type: "consulate_general",
      country: "AW", region: "caribbean",
      address: {
        street_line1: "#1 Bilderdijkstraat",  # founder paste had "Bilderdilkstraat" — corrected obvious typo (Dutch street name)
        street_line2: nil,
        locality: "Oranjestad",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+297 585-9211", email: nil }
    },
    {
      id: "HT-EMB-MAD", name: "Madrid", type: "embassy",
      country: "ES", region: "europe",
      address: {
        street_line1: "Calle de Felipe IV 4",
        street_line2: nil,
        locality: "Madrid",
        region: nil,
        postal_code: "28014",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+34 91 575 26 24", email: nil }
    },
    {
      id: "HT-EMB-LON", name: "London", type: "embassy",
      country: "GB", region: "europe",
      address: {
        street_line1: "15 Elvaston Place",
        street_line2: nil,
        locality: "London",
        region: nil,
        postal_code: "SW7 5QF",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+44 20 3771 1427", email: nil }
    },
    {
      id: "HT-CON-TCI", name: "Providenciales, Turks & Caicos", type: "consulate_general",
      country: "TC", region: "caribbean",
      address: {
        street_line1: "1229 Leeward Highway",
        street_line2: nil,
        locality: "Providenciales",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+1 649 649 4331", email: nil }
    },
    {
      id: "HT-EMB-TYO", name: "Tokyo", type: "embassy",
      country: "JP", region: "asia",
      address: {
        street_line1: "4-12-24 Nishi-Azabu",
        street_line2: nil,
        locality: "Tokyo",
        region: "Minato-ku",
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+81 3 3486 7096", email: nil }
    },
    {
      id: "HT-EMB-DOH", name: "Doha", type: "embassy",
      country: "QA", region: "middle_east",
      address: {
        street_line1: "Villa 10, Saha 31, Zone 66",
        street_line2: "Jasmine Court",
        locality: "Doha",
        region: nil,
        postal_code: nil,            # Qatar has no postal-code system
        latitude: nil, longitude: nil
      },
      contact: { phone: "+974 3133 2215", email: nil }
    },
    {
      id: "HT-EMB-TPE", name: "Taipei", type: "embassy",
      country: "TW", region: "asia",
      address: {
        street_line1: "No. 9-1, Lane 62, Tianmu West Rd",
        street_line2: nil,
        locality: "Taipei",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+886 2 2876 6718", email: nil }
    },
    {
      id: "HT-EMB-HAN", name: "Hanoi", type: "embassy",
      country: "VN", region: "asia",
      address: {
        street_line1: "44B Ly Thuong Kiet",
        street_line2: "Hoan Kiem",
        locality: "Hanoi",
        region: nil,
        postal_code: nil,
        latitude: nil, longitude: nil
      },
      contact: { phone: "+84 24 7107 8888", email: nil }
    },
    # ── New entries (not in original 42-mission set) ────────────────
    {
      id: "HT-EMB-PRE", name: "Pretoria", type: "embassy",
      country: "ZA", region: "africa",
      address: {
        street_line1: "246 Carina Street",
        street_line2: "Waterkloof Ridge",
        locality: "Pretoria",
        region: nil,
        postal_code: "0181",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+27 12 342 0192", email: nil }
    },
    {
      id: "HT-EMB-PEK", name: "Beijing", type: "embassy",
      country: "CN", region: "asia",
      address: {
        # Founder paste: "1, Xin Dong Lu, 3-1-72 Ta Yuan Diplomatic
        # Compound, Chaoyang District, 100600". Rendered in international
        # form (smallest-to-largest); building/compound on line1, street
        # on line2.
        street_line1: "3-1-72 Ta Yuan Diplomatic Compound",
        street_line2: "1 Xin Dong Lu, Chaoyang District",
        locality: "Beijing",
        region: nil,
        postal_code: "100600",
        latitude: nil, longitude: nil
      },
      contact: { phone: "+86 10 6532 4043", email: nil }
    }
  ].freeze

  # ── ALL MISSIONS ───────────────────────────────────────────────
  ALL_MISSIONS = (US_MISSIONS + DR_MISSIONS + AMERICAS_MISSIONS + EUROPE_OTHER_MISSIONS).freeze

  # Voting stations — consulates and embassies that can host diaspora voting
  VOTING_STATIONS = ALL_MISSIONS.freeze

  # Regions for grouping
  REGIONS = {
    "north_america" => "Amerik di Nò",
    "caribbean"     => "Karayib",
    "south_america" => "Amerik di Sid",
    "central_america" => "Amerik Santral",
    "europe"        => "Ewòp",
    "asia"          => "Azi",
    "middle_east"   => "Mwayen Oryan",
    "africa"        => "Afrik"
  }.freeze

  # Mission types
  MISSION_TYPES = {
    "embassy"           => "Anbasad",
    "consulate_general" => "Konsila Jeneral",
    "consulate"         => "Konsila"
  }.freeze

  class_methods do
    def missions_by_country(country_code)
      ALL_MISSIONS.select { |m| m[:country] == country_code }
    end

    def missions_by_region(region)
      ALL_MISSIONS.select { |m| m[:region] == region }
    end

    def voting_countries
      ALL_MISSIONS.map { |m| m[:country] }.uniq.sort
    end

    # Returns the static address hash for a mission ID, or {} if the
    # mission has no address data populated yet (older entries that
    # haven't been verified against primary sources). Use to seed a
    # ElectionMissionParticipation row's structured-address columns.
    def structured_address(mission_id)
      m = ALL_MISSIONS.find { |x| x[:id] == mission_id }
      m && m[:address] ? m[:address] : {}
    end

    # Returns the static contact hash (phone/email) for a mission ID.
    # Same nil-safe semantics as structured_address.
    def default_contact(mission_id)
      m = ALL_MISSIONS.find { |x| x[:id] == mission_id }
      m && m[:contact] ? m[:contact] : {}
    end
  end

  # Module-level accessors so rake tasks / one-off scripts can call
  # HaitianDiplomaticMissions.structured_address(...) without including
  # the concern. They delegate to the class_methods versions above.
  def self.structured_address(mission_id)
    m = ALL_MISSIONS.find { |x| x[:id] == mission_id }
    m && m[:address] ? m[:address] : {}
  end

  def self.default_contact(mission_id)
    m = ALL_MISSIONS.find { |x| x[:id] == mission_id }
    m && m[:contact] ? m[:contact] : {}
  end

  # Priority country codes for dropdowns — ordered by diaspora population size.
  # Countries with Haitian diplomatic missions + key diaspora territories.
  PRIORITY_COUNTRY_CODES = %w[
    HT US DO CA FR BR BS CL MX CU JM
    GP MQ GF TT PA CO EC VE AR SR
    BE DE ES GB IT JP QA TW VN ZA CN
  ].freeze
end
