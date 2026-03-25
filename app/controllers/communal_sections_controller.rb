class CommunalSectionsController < ApplicationController
  def postal_code
    section = CommunalSection.find(params[:id])
    render json: { postal_code: section.postal_code }
  end
end
