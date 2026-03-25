# app/controllers/addresses_controller.rb
class AddressesController < ApplicationController
  def arrondissements
    department = Department.find_by(id: params[:department_id])
    unless department
      render json: { error: "Department not found" }, status: :not_found
      return
    end
    render json: department.arrondissements.map { |a| { id: a.id, name: a.name } }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Department not found" }, status: :not_found
  end

  def communes
    arrondissement = Arrondissement.find_by(id: params[:arrondissement_id])
    unless arrondissement
      render json: { error: "Arrondissement not found" }, status: :not_found
      return
    end
    render json: arrondissement.communes.map { |c| { id: c.id, name: c.name } }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Arrondissement not found" }, status: :not_found
  end

  def communal_sections
    commune = Commune.find_by(id: params[:commune_id])
    unless commune
      render json: { error: "Commune not found" }, status: :not_found
      return
    end
    render json: commune.communal_sections.map { |cs| { id: cs.id, name: cs.name } }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Commune not found" }, status: :not_found
  end

  def postal_codes
    communal_section = CommunalSection.find_by(id: params[:communal_section_id])
    unless communal_section
      render json: { error: "Communal Section not found" }, status: :not_found
      return
    end
    commune = communal_section.commune
    arrondissement = commune.arrondissement
    department = arrondissement.department
    postal_code = "HT#{department.postal_code_prefix}#{arrondissement.postal_code_digit}#{commune.postal_code_digit}#{communal_section.postal_code_digit}"
    render json: { postal_code: postal_code }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Communal Section not found" }, status: :not_found
  end
end





# # app/controllers/addresses_controller.rb
# class AddressesController < ApplicationController
#   def arrondissements
#     department = Department.find(params[:id])
#     arrondissements = department.arrondissements
#     render json: arrondissements.map { |a| { id: a.id, name: a.name } }
#   end

#   def communes
#     arrondissement = Arrondissement.find(params[:id])
#     communes = arrondissement.communes
#     render json: communes.map { |c| { id: c.id, name: c.name } }
#   end

#   def communal_sections
#     commune = Commune.find(params[:id])
#     communal_sections = commune.communal_sections
#     render json: communal_sections.map { |cs| { id: cs.id, name: cs.name } }
#   end

#   def postal_code
#     communal_section = CommunalSection.find(params[:id])
#     commune = communal_section.commune
#     arrondissement = commune.arrondissement
#     department = arrondissement.department

#     postal_code = "HT#{department.postal_code_prefix}#{arrondissement.postal_code_digit}#{commune.postal_code_digit}#{communal_section.postal_code_digit}"
#     render json: { postal_code: postal_code }
#   end
# end