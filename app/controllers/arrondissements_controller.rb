# app/controllers/arrondissements_controller.rb
class ArrondissementsController < ApplicationController
  def communes
    arrondissement = Arrondissement.find(params[:id])
    render json: arrondissement.communes.select(:id, :name)
  end
end


