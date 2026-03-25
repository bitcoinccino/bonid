# app/models/department.rb
class Department < ApplicationRecord
  has_many :arrondissements
  has_many :communes

  before_save :set_slug

  # === Public Methods ===
  def to_param
    slug
  end

  # Used by Stimulus address controller to map department IDs to slugs
  # Example output: { 1 => "ouest", 2 => "nord", 3 => "artibonite" }
  def self.slug_map
    all.pluck(:id, :slug).to_h
  end

  private

  def set_slug
    self.slug = name.parameterize if slug.blank?
  end
end
