# app/controllers/addresses_controller.rb
class AddressesController < ApplicationController
  def arrondissements
    department = Department.find(params[:id])
    arrondissements = department.arrondissements
    render json: arrondissements.map { |a| { id: a.id, name: a.name } }
  end

  def communes
    arrondissement = Arrondissement.find(params[:id])
    communes = arrondissement.communes
    render json: communes.map { |c| { id: c.id, name: c.name } }
  end

  def communal_sections
    commune = Commune.find(params[:id])
    communal_sections = commune.communal_sections
    render json: communal_sections.map { |cs| { id: cs.id, name: cs.name } }
  end

  def postal_code
    communal_section = CommunalSection.find(params[:id])
    commune = communal_section.commune
    arrondissement = commune.arrondissement
    department = arrondissement.department

    postal_code = "HT#{department.postal_code_prefix}#{arrondissement.postal_code_digit}#{commune.postal_code_digit}#{communal_section.postal_code_digit}"
    render json: { postal_code: postal_code }
  end
end