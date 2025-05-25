# app/controllers/communes_controller.rb
class CommunesController < ApplicationController
  def communal_sections
    commune = Commune.find(params[:id])
    render json: commune.communal_sections.select(:id, :name)
  end
end
