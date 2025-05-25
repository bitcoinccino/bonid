class Arrondissement < ApplicationRecord
  belongs_to :department
  has_many :communes, dependent: :destroy
end
