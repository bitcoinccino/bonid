# frozen_string_literal: true

# Plural rule for Haitian Creole (ht): same as French — :one for 0 and 1,
# :other for everything else.
#
# Lives in config/locales (not an initializer) so it is re-loaded with the
# YAML files whenever I18n reloads in development. An after_initialize
# store_translations gets wiped on the first locale-file edit, which raised
# "Translation missing: ht.i18n.plural.rule".
{
  ht: {
    i18n: {
      plural: {
        keys: %i[one other],
        rule: ->(n) { n.zero? || n == 1 ? :one : :other }
      }
    }
  }
}
