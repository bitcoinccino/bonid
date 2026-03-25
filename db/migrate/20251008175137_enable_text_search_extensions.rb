# db/migrate/XXXXXXXXXXXX_enable_text_search_extensions.rb
class EnableTextSearchExtensions < ActiveRecord::Migration[7.1]
  def change
    enable_extension "unaccent"
    enable_extension "pg_trgm"
  end
end
