class LocationsController < ApplicationController
  def arrondissements
    arrondissements = Arrondissement.where(department_id: params[:department_id])
    render json: arrondissements.select(:id, :name)
  end

  def communes
    communes = Commune.where(arrondissement_id: params[:arrondissement_id])
    render json: communes.select(:id, :name)
  end

  def communal_sections
    sections = CommunalSection.where(commune_id: params[:commune_id])
    render json: sections.select(:id, :name)
  end
end

