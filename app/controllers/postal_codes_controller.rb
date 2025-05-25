# app/controllers/postal_codes_controller.rb
class PostalCodesController < ApplicationController
  def lookup
    section = CommunalSection.find_by(id: params[:id])
    if section
      render json: { postal_code: section.postal_code }
    else
      render json: { postal_code: "HT0000" }, status: :not_found
    end
  end
end