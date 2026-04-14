# frozen_string_literal: true

# Haitian Creole (ht) uses the same plural rules as French:
# one for 0 and 1, other for everything else.
# Without this, time_ago_in_words and other pluralized helpers
# raise: Translation missing: ht.i18n.plural.rule

I18n.backend.class.include(I18n::Backend::Pluralization)

# Store the plural rule for :ht after backend is initialized
Rails.application.config.after_initialize do
  I18n.backend.store_translations :ht, i18n: {
    plural: {
      rule: ->(n) { n == 0 || n == 1 ? :one : :other }
    }
  }
end
