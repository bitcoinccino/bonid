# frozen_string_literal: true

require "rails_helper"

# Every citizen-facing alert must exist in all three portal languages with
# the same %{placeholders}; otherwise production silently falls back to
# English (config.i18n.fallbacks = true).
RSpec.describe "alerts.* translations" do
  def flatten(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), out|
      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? out.merge!(flatten(value, path)) : out[path] = value
    end
  end

  let(:locales) do
    %w[en fr ht].to_h do |l|
      [ l, flatten(YAML.load_file(Rails.root.join("config/locales/alerts.#{l}.yml"))[l]) ]
    end
  end

  it "has the same keys in en, fr and ht" do
    en_keys = locales["en"].keys.sort
    %w[fr ht].each do |l|
      expect(locales[l].keys.sort).to eq(en_keys), "alerts.#{l}.yml keys differ from en"
    end
  end

  it "uses the same placeholders in every language" do
    locales["en"].each do |key, en_value|
      expected = en_value.scan(/%\{(\w+)\}/).flatten.sort
      %w[fr ht].each do |l|
        actual = locales[l][key].to_s.scan(/%\{(\w+)\}/).flatten.sort
        expect(actual).to eq(expected), "#{l}: #{key} placeholders #{actual} != en #{expected}"
      end
    end
  end

  it "has no blank translations" do
    locales.each do |l, entries|
      blank = entries.select { |_, v| v.to_s.strip.empty? }.keys
      expect(blank).to be_empty, "#{l} has blank values: #{blank.join(', ')}"
    end
  end
end
