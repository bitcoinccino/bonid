class PhysicalProfile < ApplicationRecord
  belongs_to :user

  # === Enumerations ===
  enum :eye_color, {
    black_eye: "black_eye",
    brown_eye: "brown_eye",
    blue_eye: "blue_eye",
    green_eye: "green_eye",
    gray_eye: "gray_eye",
    hazel_eye: "hazel_eye"
  }

  enum :hair_color, {
    black_hair: "black_hair",
    dark_brown_hair: "dark_brown_hair",
    brown_hair: "brown_hair",
    blonde_hair: "blonde_hair",
    gray_hair: "gray_hair",
    red_hair: "red_hair"
  }

  enum :hair_style, {
    short: "short",
    bald: "bald",
    afro: "afro",
    dreadlocks: "dreadlocks",
    braids: "braids",
    twists: "twists",
    cornrows: "cornrows",
    fade: "fade",
    curly: "curly",
    straight: "straight"
  }

  enum :race, {
    black: "black",
    mixed: "mixed",
    white: "white",
    asian: "asian",
    other: "other"
  }

  enum :body_type, {
    slim: "slim",
    avg_build: "average",
    athletic: "athletic",
    muscular: "muscular",
    heavy: "heavy"
  }

  enum :skin_tone, {
    very_light: "very_light",
    light: "light",
    medium: "medium",
    tan: "tan",
    brown: "brown",
    dark: "dark"
  }

  enum :facial_hair, {
    none_present: "none",
    beard: "beard",
    mustache: "mustache",
    goatee: "goatee"
  }

  enum :handedness, {
    left: "left",
    right: "right",
    ambidextrous: "ambidextrous"
  }

  # === Scalable Field Definition ===
  FIELD_DEFINITIONS = {
    height_cm: {
      type: :number,
      label: "Height (cm)",
      placeholder: "Enter height in centimeters"
    },
    weight_kg: {
      type: :number,
      label: "Weight (kg)",
      placeholder: "Enter weight in kilograms"
    },
    eye_color: {
      type: :select,
      label: "Eye Color",
      options: -> { PhysicalProfile.eye_colors.keys.map { |k| [ k.humanize.titleize, k ] } }
    },
    hair_color: {
      type: :select,
      label: "Hair Color",
      options: -> { PhysicalProfile.hair_colors.keys.map { |k| [ k.humanize.titleize, k ] } }
    },
    hair_style: {
      type: :select,
      label: "Hair Style",
      options: -> { PhysicalProfile.hair_styles.keys.map { |k| [ k.humanize.titleize, k ] } }
    },
    race: {
      type: :select,
      label: "Race / Ethnicity",
      options: -> { PhysicalProfile.races.keys.map { |k| [ k.humanize.titleize, k ] } }
    },
    body_type: {
      type: :select,
      label: "Body Type",
      options: -> { PhysicalProfile.body_types.keys.map { |k| [ k.humanize.titleize, k ] } }
    },
    skin_tone: {
      type: :select,
      label: "Skin Tone",
      options: -> { PhysicalProfile.skin_tones.keys.map { |k| [ k.humanize.titleize, k ] } }
    },
    facial_hair: {
      type: :select,
      label: "Facial Hair",
      options: -> { PhysicalProfile.facial_hairs.keys.map { |k| [ k.humanize.titleize, k ] } }
    },
    handedness: {
      type: :select,
      label: "Handedness",
      options: -> { PhysicalProfile.handednesses.keys.map { |k| [ k.humanize.titleize, k ] } }
    }
  }.freeze
end
