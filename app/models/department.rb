class Department < ApplicationRecord
  has_many :arrondissements
  has_many :communes

  before_save :set_slug

  def to_param
    slug
  end

  private

  def set_slug
    self.slug = name.parameterize if slug.blank?
  end
end
