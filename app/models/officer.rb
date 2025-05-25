class Officer < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable
  
  validates :password, presence: true, confirmation: true, on: :update, if: :invitation_token_present?

def invitation_token_present?
  invitation_token.present? && invitation_accepted_at.nil?
end


  belongs_to :partner
  has_many :incident_reports, dependent: :destroy

  enum :status, { invited: 0, active: 1, revoked: 2 }

  enum :role, {
    officer: 0,
    director_general: 1,
    inspector_general: 2, # ← Typo fix here
    agent: 3,
    admin: 4
  }

  before_create :generate_invitation_token

  validates :email, presence: true, uniqueness: true
  validates :full_name, :badge_id, presence: true

  def self.unit_options = {
      "BOID" => ["Opérations Tactiques", "Intervention Départementale"], # Brigade d'Opération et d'Intervention Départementale: Tactical and regional operations
      "BRI" => ["Enquête Criminelle", "Intervention Rapide"], # Brigade de Recherche et d'Intervention: Criminal investigation and rapid response (inferred)
      "EDUPOL" => ["Éducation Communautaire", "Sécurité Scolaire"], # Police Éducative et Communautaire: Community education and school safety
      "POLIFRONT" => ["Sécurité Frontalière", "Opérations de Point de Contrôle"], # Police Frontalière: Land border security and checkpoints
      "SWAT" => ["Entrée Tactique", "Tireur d'Élite", "Négociation"], # Special Weapons and Tactics: Tactical entry, sniping, and negotiation
      "POLITOUR" => ["Protection Touristique", "Surveillance des Sites"], # Police Touristique: Tourist protection and site surveillance
      "UTAG" => ["Opérations Anti-Gang", "Réponse Tactique"], # Unité Temporaire Anti-Gang: Anti-gang operations
      "CIMO" => ["Contrôle des Foules", "Réponse Rapide"], # Corps d’Intervention et de Maintien de l’Ordre: Crowd control and public order
      "UDMO" => ["Patrouille Urbaine", "Opérations à Haut Risque"], # Unité Départementale de Maintien de l’Ordre: Urban patrol and high-risk operations
      "BLTS" => ["Lutte Antidrogue", "Interdiction de Stupéfiants"], # Brigade de Lutte contre le Trafic de Stupéfiants: Counternarcotics
      "USGPN" => ["Sécurité du Palais", "Protection des VIP"], # Unité de Sécurité Générale du Palais National: National Palace security
      "USP" => ["Sécurité Présidentielle", "Protection Rapprochée"], # Unité de Sécurité Présidentielle: Presidential protection
      "BIM" => ["Patrouille Maritime", "Sécurité Côtière"], # Brigade d'Intervention Maritime: Maritime and coast guard operations
      "BAFE" => ["Enquête Financière", "Protection Économique"] # Bureau des Affaires Financières et Économiques: Financial and economic crime investigation
    }
    

  private

  def generate_invitation_token
    self.invitation_token = SecureRandom.hex(20)
  end
  
end
