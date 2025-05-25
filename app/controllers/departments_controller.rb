# app/controllers/departments_controller.rb
class DepartmentsController < ApplicationController
  def arrondissements
    department = Department.find_by!(slug: params[:slug])
    render json: department.arrondissements.select(:id, :name)
  end
end