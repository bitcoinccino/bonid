# app/models/concerns/officer_constants.rb
module OfficerConstants
  extend ActiveSupport::Concern

  # -----------------------------------------
  # RANKS (Grades de la PNH)
  # -----------------------------------------
  RANKS = [
    "Directeur Général",
    "Inspecteur Général",
    "Commissaire Divisionnaire",
    "Commissaire Principal",
    "Commissaire de Police",
    "Sous-Commissaire",
    "Inspecteur Divisionnaire",
    "Inspecteur Principal",
    "Inspecteur de Police",
    "Agent Principal",
    "Agent III",
    "Agent II",
    "Agent I"
  ].freeze unless const_defined?(:RANKS)

  # -----------------------------------------
  # UNITS WITH SPECIALTIES
  # -----------------------------------------
  UNIT_OPTIONS = {
    "DCPJ"      => [ "Police Scientifique (SPS)", "Affaires Criminelles (BAC)", "Bureau des Affaires Financières (BAFE)", "Brigade de Protection des Mineurs (BPM)" ],
    "DCPR"      => [ "Constat d'Accident", "Sécurité Routière", "Service de Circulation" ],
    "UTAG"      => [ "Opérations Anti-Gang", "Réponse Tactique" ],
    "BOID"      => [ "Opérations Tactiques", "Intervention Départementale" ],
    "BRI"       => [ "Enquête Criminelle", "Intervention Rapide" ],
    "SWAT"      => [ "Entrée Tactique", "Tireur d'Élite", "Négociation" ],
    "CIMO"      => [ "Contrôle des Foules", "Maintien de l'Ordre" ],
    "UDMO"      => [ "Patrouille Urbaine", "Opérations à Haut Risque" ],
    "BLTS"      => [ "Lutte Antidrogue", "Interdiction de Stupéfiants" ],
    "POLIFRONT" => [ "Sécurité Frontalière", "Opérations de Point de Contrôle" ],
    "POLITOUR"  => [ "Protection Touristique", "Surveillance des Sites" ],
    "POLAER"    => [ "Police Aéroportuaire", "Sécurité du Transport Aérien" ],
    "BIM"       => [ "Patrouille Maritime", "Sécurité Côtière" ],
    "USGPN"     => [ "Sécurité du Palais National", "Protection des Hautes Personnalités" ],
    "USP"       => [ "Sécurité Présidentielle", "Protection Rapprochée" ],
    "EDUPOL"    => [ "Éducation Communautaire", "Sécurité Scolaire" ]
  }.freeze unless const_defined?(:UNIT_OPTIONS)

  # -----------------------------------------
  # OFFICER MISCONDUCT & COMPLAINTS
  # Mapped for IGPNH (Inspection Générale)
  # -----------------------------------------
  COMPLAINT_TYPES = {
    "Usage de la force" => [
      "Brutalité physique",
      "Blessures par balle",
      "Torture",
      "Usage excessif d'arme à feu"
    ],
    "Corruption" => [
      "Racket / Pot-de-vin",
      "Détournement de preuves",
      "Trafic de drogue",
      "Extorsion"
    ],
    "Abus de pouvoir" => [
      "Arrestation arbitraire",
      "Séquestration",
      "Menaces de mort",
      "Perquisition illégale"
    ],
    "Inconduite" => [
      "Refus de service",
      "Déni de soins médicaux",
      "Harcèlement sexuel",
      "Insubordination"
    ]
  }.freeze unless const_defined?(:COMPLAINT_TYPES)

  # -----------------------------------------
  # INVESTIGATION WORKFLOW
  # Tracking progress of Internal Affairs (IGPNH)
  # -----------------------------------------
  COMPLAINT_STATUSES = [
    "Signalé",            # Reported
    "En cours d'examen",  # Under review
    "Enquête ouverte",    # Investigation active
    "Référé au Tribunal", # Referred to Judiciary
    "Sanction administrative", # Internally sanctioned
    "Classé sans suite"   # Dismissed
  ].freeze unless const_defined?(:COMPLAINT_STATUSES)

  # -----------------------------------------
  # ROUTING & GEOGRAPHY
  # -----------------------------------------
  ENTRY_MODE_UNITS = {
    air:  "POLAER",
    sea:  "BIM",
    land: "POLIFRONT"
  }.freeze unless const_defined?(:ENTRY_MODE_UNITS)
  # -----------------------------------------
  # DEPARTMENTAL DIRECTORATES (Directions Départementales)
  # -----------------------------------------
  DEPARTMENTS = {
    "DDO"   => "Direction Départementale de l'Ouest",
    "DDN"   => "Direction Départementale du Nord",
    "DDS"   => "Direction Départementale du Sud",
    "DDA"   => "Direction Départementale de l'Artibonite",
    "DDNE"  => "Direction Départementale du Nord-Est",
    "DDNO"  => "Direction Départementale du Nord-Ouest",
    "DDSE"  => "Direction Départementale du Sud-Est",
    "DDC"   => "Direction Départementale du Centre",
    "DDGA"  => "Direction Départementale de la Grand'Anse",
    "DDNIP" => "Direction Départementale des Nippes"
  }.freeze unless const_defined?(:DEPARTMENTS)

  # ============================================================
  # ACCESS CONTROL CONSTANTS
  # Used by OfficerAccessControl concern — do not modify without
  # updating the concern and its tests.
  # ============================================================

  # Maps each rank string to one of three permission groups:
  #   :field      — can create reports, view own cases only
  #   :supervisor — can view all unit reports, approve/reject/reassign
  #   :strategic  — cross-unit visibility, national analytics, full partner view
  RANK_GROUPS = {
    "Agent I"                  => :field,
    "Agent II"                 => :field,
    "Agent III"                => :field,
    "Agent Principal"          => :field,
    "Inspecteur de Police"     => :supervisor,
    "Inspecteur Principal"     => :supervisor,
    "Inspecteur Divisionnaire" => :supervisor,
    "Sous-Commissaire"         => :supervisor,
    "Commissaire de Police"    => :strategic,
    "Commissaire Principal"    => :strategic,
    "Commissaire Divisionnaire"=> :strategic,
    "Inspecteur Général"       => :strategic,
    "Directeur Général"        => :strategic
  }.freeze unless const_defined?(:RANK_GROUPS)

  # Maps each unit to the crime category keys it is authorised to file.
  # Category keys must match IncidentReport::CRIME_TYPES (or CrimeConstants).
  # Supervisors and strategic officers bypass this filter (they see all types).
  UNIT_CRIME_TYPES = {
    "DCPJ"      => %w[violent_crimes economic_crimes organized_crime],
    "BLTS"      => %w[organized_crime smuggling_and_trafficking],
    "UTAG"      => %w[organized_crime violent_crimes],
    "SWAT"      => %w[organized_crime violent_crimes],
    "BRI"       => %w[violent_crimes organized_crime],
    "CIMO"      => %w[social_and_emerging_crimes traffic_and_minor_infractions],
    "UDMO"      => %w[social_and_emerging_crimes violent_crimes],
    "BOID"      => %w[violent_crimes property_crimes social_and_emerging_crimes],
    "DCPR"      => %w[traffic_and_minor_infractions],
    "POLIFRONT" => %w[smuggling_and_trafficking organized_crime],
    "POLITOUR"  => %w[property_crimes traffic_and_minor_infractions social_and_emerging_crimes],
    "POLAER"    => %w[smuggling_and_trafficking organized_crime],
    "BIM"       => %w[smuggling_and_trafficking organized_crime],
    "USGPN"     => %w[political_and_state_crimes violent_crimes],
    "USP"       => %w[political_and_state_crimes violent_crimes],
    "EDUPOL"    => %w[social_and_emerging_crimes traffic_and_minor_infractions]
  }.freeze unless const_defined?(:UNIT_CRIME_TYPES)

  # BonID lookup capability per unit:
  #   "full"    — complete criminal history, identity profile
  #   "limited" — wanted/criminal status check only (privacy-restricted units)
  #   "standard"— standard identity verification
  BONID_ACCESS_LEVELS = {
    "full"     => %w[DCPJ POLIFRONT BLTS BRI UTAG SWAT USGPN USP],
    "limited"  => %w[EDUPOL POLITOUR DCPR],
    "standard" => %w[CIMO UDMO BOID POLAER BIM]
  }.freeze unless const_defined?(:BONID_ACCESS_LEVELS)

  # Reverse lookup: unit_name → access level string (e.g. "DCPJ" => "full")
  UNIT_BONID_ACCESS = BONID_ACCESS_LEVELS.each_with_object({}) do |(level, units), h|
    units.each { |u| h[u] = level }
  end.freeze unless const_defined?(:UNIT_BONID_ACCESS)

  # "Need to Know" override rules.
  # joint_task_force: DCPJ + SWAT gain cross-unit visibility for kidnapping/hostage reports.
  # internal_affairs: Police Brutality reports locked to Inspector General role only.
  # high_severity_alert: severity 4-5 triggers cross-unit notification (not visibility).
  UNIT_ACCESS_SCOPE = {
    joint_task_force: {
      trigger_crime_types: [ "Kidnapping", "Child Abduction" ],
      authorized_units:    %w[DCPJ SWAT]
    },
    internal_affairs: {
      trigger_crime_types: [ "Police Brutality" ],
      authorized_units:    []   # enforced via inspector_general role check
    },
    high_severity_alert: {
      min_severity:      4,
      authorized_groups: [ :strategic ]
    }
  }.freeze unless const_defined?(:UNIT_ACCESS_SCOPE)

  # Units whose reports are always restricted to same-unit officers
  # (unless strategic rank or matching role override).
  RESTRICTED_UNITS = %w[USGPN USP].freeze unless const_defined?(:RESTRICTED_UNITS)
end
