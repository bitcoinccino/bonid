# frozen_string_literal: true

# Enable CLDR-style pluralization lookups (reads i18n.plural.rule per locale).
# The Haitian Creole rule itself lives in config/locales/plurals.rb so it
# survives I18n reloads in development.
I18n.backend.class.include(I18n::Backend::Pluralization)
