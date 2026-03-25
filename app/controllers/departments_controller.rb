# app/controllers/departments_controller.rb
class DepartmentsController < ApplicationController
  def arrondissements
    department = Department.find_by!(slug: params[:slug])
    render json: department.arrondissements.select(:id, :name)
  end

  # Direct department → communes lookup (skips arrondissement level)
  def communes
    department = Department.find(params[:id])
    render json: department.communes.order(:name).select(:id, :name)
  end
end