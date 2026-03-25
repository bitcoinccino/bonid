module CrimeConstants
  # Severity Levels (used to describe risk level)
  SEVERITY_LABELS = {
    1 => "Low",
    2 => "Minor",
    3 => "Moderate",
    4 => "Serious",
    5 => "Severe"
  }.freeze

  # Severity Mapping (used for badge logic, statistics, etc.)
  CRIME_SEVERITY = {
    "homicide" => 5, "sexual violence" => 5, "kidnapping" => 5, "assault" => 4, "torture" => 5,
    "lynching" => 4, "police brutality" => 4, "domestic violence" => 4, "gang violence" => 4,
    "armed robbery" => 4, "arson" => 4, "drug trafficking" => 5, "human trafficking" => 5,
    "arms trafficking" => 5, "organized crime" => 5, "financial fraud" => 3, "cybercrime" => 3,
    "public disorder" => 2, "traffic violation" => 1
  }.freeze

  # Crime Codes (used for display or report labeling)
  CRIME_CODES = {
    "homicide" => "HOMO", "sexual violence" => "SEXV", "kidnapping" => "KIDN", "assault" => "ASSA",
    "torture" => "TORT", "lynching" => "LYNC", "police brutality" => "POLB", "domestic violence" => "DOMV",
    "child abduction" => "CHAB", "hate crimes" => "HATE", "gang violence" => "GANG", "mutilation" => "MUTI",
    "armed assault" => "ARMA", "human sacrifice" => "HUSR", "stalking" => "STAL", "mass murder" => "MASM",
    "serial killing" => "SERK", "ethnic cleansing" => "ETHC", "armed robbery" => "AROB", "burglary" => "BURG",
    "theft" => "THEF", "carjacking" => "CARJ", "home invasion" => "HOME", "vandalism" => "VAND",
    "arson" => "ARSO", "larceny" => "LARC", "shoplifting" => "SHOP", "fencing stolen goods" => "FENC",
    "art theft" => "ARTT", "livestock theft" => "LIVE", "drug trafficking" => "DRUG", "human trafficking" => "HUMT",
    "arms trafficking" => "ARMT", "organized crime" => "ORGC", "racketeering" => "RACK", "extortion" => "EXTO",
    "money laundering" => "MONE", "piracy" => "PIRA", "contract killing" => "CONT", "illegal betting syndicates" => "BETS",
    "protection rackets" => "PROT", "organ harvesting" => "ORGH", "cyber extortion" => "CYBE", "sex trafficking" => "SEXT",
    "labor trafficking" => "LABT", "child trafficking" => "CHTR", "forced marriage trafficking" => "FMAR",
    "debt bondage trafficking" => "DEBT", "nuclear material trafficking" => "NUCT", "chemical weapons trafficking" => "CHEM",
    "financial fraud" => "FRAU", "embezzlement" => "EMBE", "corruption" => "CORR", "counterfeiting" => "COUN",
    "identity theft" => "IDEN", "illegal gambling" => "GAMB", "tax evasion" => "TAXE", "bribery" => "BRIB",
    "ponzi schemes" => "PONZ", "insider trading" => "INSI", "corporate espionage" => "ESPI", "price fixing" => "PRIC",
    "workplace bribery" => "WORK", "nepotism" => "NEPO", "cronyism" => "CRON", "kickback schemes" => "KICK",
    "falsified expense reports" => "FALS", "abuse of authority" => "ABUS", "fuel smuggling" => "FUEL",
    "smuggling of goods" => "SMUG", "wildlife trafficking" => "WILD", "blackmail" => "BLAC",
    "antiquities smuggling" => "ANTI", "tobacco smuggling" => "TOBA", "pharmaceutical trafficking" => "PHAR",
    "human organ trafficking" => "HORG", "exotic pet trafficking" => "EXOT", "child exploitation" => "CHEX",
    "forced displacement" => "FORC", "environmental crime" => "ENVI", "election-related violence" => "ELEC",
    "prison breaks" => "PRIS", "cybercrime" => "CYBR", "public disorder" => "PUBD", "terrorism" => "TERR",
    "land disputes" => "LAND", "revenge pornography" => "REVP", "online harassment" => "HARA",
    "deepfake fraud" => "DEEP", "cryptocurrency scams" => "CRYP", "food contamination" => "FOOD",
    "vigilantism" => "VIGI", "bioterrorism" => "BIOT", "cyberterrorism" => "CYBT", "ecocide" => "ECOC",
    "illegal protest assembly" => "PROA", "protest incitement" => "PROI", "protest-related arson" => "PRAR",
    "protest-related assault" => "PRAS", "barricade destruction" => "BARR", "traffic violation" => "TRAF",
    "driving without license" => "DRIV", "vehicle registration violation" => "VEHI", "public nuisance" => "NUIS",
    "littering" => "LITT", "trespassing" => "TRES", "minor vandalism" => "MINV", "disorderly conduct" => "DISC",
    "jaywalking" => "JAYW", "illegal parking" => "PARK", "noise violations" => "NOIS", "public intoxication" => "INTO",
    "loitering" => "LOIT", "petty theft" => "PETT", "treason" => "TREA", "espionage" => "ESPO",
    "sedition" => "SEDI", "election tampering" => "TAMP", "state-sanctioned violence" => "STAT",
    "propaganda dissemination" => "PROP", "coup d'état" => "COUP", "war crimes" => "WARC",
    "genocide" => "GENO", "crimes against humanity" => "CRIM", "state-sponsored terrorism" => "STSP",
    "protest-driven sedition" => "PSED", "anti-government protest conspiracy" => "ANTI",
    "illegal drug manufacturing" => "DRGM", "food adulteration" => "FOAD", "public health violations" => "HEAL",
    "hazardous waste dumping" => "WAST", "unlicensed medical practice" => "MEDI", "quarantine violations" => "QUAR",
    "vaccine fraud" => "VACC", "biological weapons use" => "BIOW", "data breaches" => "DATA",
    "hacking" => "HACK", "phishing" => "PHIS", "ransomware attacks" => "RANS", "dark web trafficking" => "DARK",
    "software piracy" => "SOFT", "ai manipulation" => "AIMA", "digital forgery" => "DIGI",
    "critical infrastructure hacking" => "INFR", "copyright infringement" => "COPY",
    "trademark counterfeiting" => "TRAD", "patent infringement" => "PATE", "trade secret theft" => "SECR",
    "counterfeit goods distribution" => "GOOD", "digital piracy" => "DPIR", "brand impersonation" => "BRAN",
    "design right violation" => "DESI", "music copyright infringement" => "MUSC",
    "unauthorized music streaming" => "STRM", "music plagiarism" => "PLAG", "bootleg recordings" => "BOOT",
    "inmate homicide" => "INHO", "prison assault" => "PRIA", "contraband smuggling in prison" => "SMUP",
    "prison guard corruption" => "GUAR", "inmate extortion" => "INEX", "prison gang activity" => "PGAN",
    "sexual exploitation in prison" => "SEXP", "escape conspiracy" => "ESCA"
  }.freeze

  # Haitian Penal Code Article Links (from 2020 Decree, effective 2025)
  # Note: The 2020 Haitian Penal Code is used, as it is the current law as of February 2026.
  # Articles are listed where directly or closely related to the crime. If not specified, noted as such.
  CRIME_ARTICLES = {
    "homicide" => "245-249, 252, 254-255, 292, 234-235, 571, 975-976",
    "sexual violence" => "296-344, 980",
    "kidnapping" => "343-345, 72-74, 647",
    "assault" => "272-295, 273-276, 564, 975-976, 265, 280",
    "torture" => "262-265, 344",
    "lynching" => "Not specified (closest: 201)",
    "police brutality" => "265, 280, 696, 344",
    "domestic violence" => "273-280, 273-276",
    "child abduction" => "343-345, 72-74",
    "hate crimes" => "207-244, 207-208, 489 (9°), 567, 980",
    "gang violence" => "201, 344, 529, 680, 912, 716",
    "mutilation" => "274-280, 344 (3°), 575",
    "armed assault" => "272-344, 273-280, 671",
    "human sacrifice" => "Not specified",
    "stalking" => "287-289, 980",
    "mass murder" => "234-235, 653",
    "serial killing" => "Not specified",
    "ethnic cleansing" => "232-233, 567, 980",
    "armed robbery" => "496",
    "burglary" => "204, 489",
    "theft" => "30, 481-482, 987",
    "carjacking" => "Not specified (closest: 356, 489)",
    "home invasion" => "205, 489",
    "vandalism" => "564-567, 991",
    "arson" => "570-576",
    "larceny" => "481-482, 987",
    "shoplifting" => "Not specified (closest: general theft articles)",
    "fencing stolen goods" => "552-553",
    "art theft" => "Not specified (closest: general theft articles)",
    "livestock theft" => "Not specified (closest: general theft articles)",
    "drug trafficking" => "254, 597, 873-877",
    "human trafficking" => "234, 892, 597, 77",
    "arms trafficking" => "597, 855-856",
    "organized crime" => "201, 846-849, 912, 529",
    "racketeering" => "710",
    "extortion" => "287, 512, 713",
    "money laundering" => "597, 599, 600",
    "piracy" => "355-357, 1004 (abrogated)",
    "contract killing" => "218",
    "illegal betting syndicates" => "Not specified",
    "protection rackets" => "Not specified",
    "organ harvesting" => "920-921",
    "cyber extortion" => "Not specified",
    "sex trafficking" => "305, 374-379, 597",
    "labor trafficking" => "597",
    "child trafficking" => "597, 374-379",
    "forced marriage trafficking" => "597",
    "debt bondage trafficking" => "597",
    "nuclear material trafficking" => "597",
    "chemical weapons trafficking" => "597",
    "financial fraud" => "528, 796, 987",
    "embezzlement" => "539, 713, 1091",
    "corruption" => "710-712, 1214",
    "counterfeiting" => "597, 808-809, 812-821, 823-826, 829-833, 835-836, 1013-1014",
    "identity theft" => "503, 725, 1011",
    "illegal gambling" => "Not specified",
    "tax evasion" => "Not specified",
    "bribery" => "710-712",
    "ponzi schemes" => "Not specified (closest: 539, 106)",
    "insider trading" => "Not specified",
    "corporate espionage" => "Not specified (closest: 125)",
    "price fixing" => "Not specified",
    "workplace bribery" => "712, 748, 1214",
    "nepotism" => "Not specified",
    "cronyism" => "Not specified",
    "kickback schemes" => "710-712",
    "falsified expense reports" => "Not specified (closest: 796)",
    "abuse of authority" => "396, 693, 712, 919",
    "fuel smuggling" => "Not specified",
    "smuggling of goods" => "597",
    "wildlife trafficking" => "903, 597",
    "blackmail" => "522, 747, 105",
    "antiquities smuggling" => "597",
    "tobacco smuggling" => "597",
    "pharmaceutical trafficking" => "Not specified",
    "human organ trafficking" => "597, 920-921",
    "exotic pet trafficking" => "597",
    "child exploitation" => "Not specified (closest: 232, 297, 303, 345, 597, 920-922)",
    "forced displacement" => "Not specified (closest: 234, 232, 350)",
    "environmental crime" => "570-571, 898-904",
    "election-related violence" => "Not specified (closest: 712, 716)",
    "prison breaks" => "777-778",
    "cybercrime" => "Not specified (closest: 286, 587-589, 592-593, 710-712, 747-748, 765-766)",
    "public disorder" => "Not specified (closest: 202, 205, 647, 716, 960)",
    "terrorism" => "211, 647-656",
    "land disputes" => "533-534, 770",
    "revenge pornography" => "Not specified (closest: 387-392)",
    "online harassment" => "Not specified (closest: 377, 593, 980)",
    "deepfake fraud" => "Not specified (closest: 589, 593, 796-800)",
    "cryptocurrency scams" => "528",
    "food contamination" => "Not specified (closest: 904, 528)",
    "vigilantism" => "Not specified (closest: 201, 680)",
    "bioterrorism" => "Not specified (closest: 572, 238)",
    "cyberterrorism" => "Not specified (closest: 647, 588-593)",
    "ecocide" => "Not specified (closest: 898, 570-571)",
    "illegal protest assembly" => "675",
    "protest incitement" => "672",
    "protest-related arson" => "Not specified (closest: 570-576)",
    "protest-related assault" => "265, 280, 672",
    "barricade destruction" => "Not specified (closest: 564)",
    "traffic violation" => "254, 292",
    "driving without license" => "254",
    "vehicle registration violation" => "Not specified",
    "public nuisance" => "Not specified (closest: 960)",
    "littering" => "986",
    "trespassing" => "204-205, 569, 1015-1016",
    "minor vandalism" => "991",
    "disorderly conduct" => "Not specified (closest: 960, 670)",
    "jaywalking" => "Not specified",
    "illegal parking" => "Not specified",
    "noise violations" => "960",
    "public intoxication" => "Not specified",
    "loitering" => "Not specified",
    "petty theft" => "987",
    "treason" => "Not specified (closest: 24, 609-619)",
    "espionage" => "Not specified (closest: 24, 612-618)",
    "sedition" => "Not specified (closest: 622-623, 716)",
    "election tampering" => "Not specified",
    "state-sanctioned violence" => "Not specified",
    "propaganda dissemination" => "Not specified (closest: 672, 716, 919)",
    "coup d'état" => "Not specified (closest: 620-621, 126, 716)",
    "war crimes" => "14, 237-238, 232/234, 914",
    "genocide" => "14, 232-233, 910",
    "crimes against humanity" => "14, 234-235, 232/234",
    "state-sponsored terrorism" => "Not specified (closest: 647)",
    "protest-driven sedition" => "Not specified (closest: 622)",
    "anti-government protest conspiracy" => "Not specified (closest: 621)",
    "illegal drug manufacturing" => "873-874, 469, 597",
    "food adulteration" => "Not specified (closest: 805, 904, 528)",
    "public health violations" => "904, 917-1016",
    "hazardous waste dumping" => "898",
    "unlicensed medical practice" => "Not specified (closest: 805, 934)",
    "quarantine violations" => "Not specified (closest: 904)",
    "vaccine fraud" => "Not specified (closest: 805)",
    "biological weapons use" => "Not specified (closest: 572, 238)",
    "data breaches" => "437-439, 592-593",
    "hacking" => "587, 765-766",
    "phishing" => "Not specified (closest: 483, 528)",
    "ransomware attacks" => "Not specified (closest: 589, 593)",
    "dark web trafficking" => "Not specified",
    "software piracy" => "Not specified (closest: 796)",
    "ai manipulation" => "Not specified (closest: 589)",
    "digital forgery" => "589, 796-800, 1011",
    "critical infrastructure hacking" => "Not specified (closest: 587)",
    "copyright infringement" => "Not specified (closest: 808-821)",
    "trademark counterfeiting" => "808-821",
    "patent infringement" => "Not specified",
    "trade secret theft" => "Not specified (closest: 593)",
    "counterfeit goods distribution" => "808-821",
    "digital piracy" => "Not specified (closest: 593)",
    "brand impersonation" => "808-821, 528",
    "design right violation" => "Not specified",
    "music copyright infringement" => "Not specified",
    "unauthorized music streaming" => "Not specified",
    "music plagiarism" => "Not specified",
    "bootleg recordings" => "Not specified",
    "inmate homicide" => "Not specified (closest: 778)",
    "prison assault" => "Not specified",
    "contraband smuggling in prison" => "Not specified",
    "prison guard corruption" => "710-712, 702",
    "inmate extortion" => "Not specified (closest: 712, 777-778, 528)",
    "prison gang activity" => "Not specified (closest: 201, 529, 716, 846)",
    "sexual exploitation in prison" => "Not specified",
    "escape conspiracy" => "777-778, 621"
  }.freeze


  # -----------------------------------------
  # TRAFFIC FINES (DCPR Standard)
  # Amounts in Gourdes (HTG)
  # -----------------------------------------
  TRAFFIC_FINES = {
    # Documentation & Licensing
    "DRIV"  => 2500,  # Conduite sans permis (No License)
    "VEHI"  => 1500,  # Plaque d'immatriculation manquante (No Tags)
    "INSUR" => 3000,  # Défaut d'assurance OAVCT (No Insurance)
    "FORGE" => 5000,  # Documents contrefaits (Forged documents)

    # Moving Violations
    "INTO"  => 5000,  # Conduite en état d'ébriété (DUI)
    "SPEED" => 2000,  # Excès de vitesse (Speeding)
    "LIGHT" => 1500,  # Griller un feu rouge (Running Red Light)
    "SIGN"  => 1000,  # Non-respect du signal "STOP" (Running Stop Sign)
    "PHONE" => 1000,  # Usage de téléphone au volant (Cell phone use)
    "ONEW"  => 1500,  # Sens unique (Driving wrong way)

    # Equipment & Environment
    "LIGHTS"=> 1000,  # Phares défectueux (Broken lights)
    "SMOKE" => 1250,  # Émission de fumée excessive (Excessive smoke)
    "HORN"  => 500,   # Usage abusif du klaxon (Abusive horn use)

    # Public Order & Parking
    "PARK"  => 250,   # Stationnement interdit (Illegal parking)
    "TRAF"  => 500,   # Infraction générale (General violation)
    "JAYW"  => 100,   # Traverser hors des clous (Jaywalking)
    "OBST"  => 2000   # Obstruction à la voie publique (Blocking traffic)
  }.freeze unless const_defined?(:TRAFFIC_FINES)
end
