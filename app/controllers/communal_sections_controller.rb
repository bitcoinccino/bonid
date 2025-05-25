# app/controllers/communal_sections_controller.rb
class CommunesController < ApplicationController
    def communal_sections
      commune = Commune.find(params[:id])
      render json: commune.communal_sections.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    end
end
  

z