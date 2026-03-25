class CommunesController < ApplicationController
  def index
    if params[:department_id].present?
      communes = Commune.where(department_id: params[:department_id])
                        .select(:id, :name)
      render json: communes
    else
      render json: [], status: :ok
    end
  end

  def communal_sections
    commune = Commune.find(params[:id])
    render json: commune.communal_sections
                        .order(:name)
                        .pluck(:id, :name)
                        .map { |id, name| { id: id, name: name } }
  end
end
