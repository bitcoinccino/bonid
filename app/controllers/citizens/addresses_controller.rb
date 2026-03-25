module Citizens
  class AddressesController < ApplicationController
    before_action :authenticate_citizen!

    def create
      @address = current_citizen.addresses.new(address_params)
      if @address.save
        redirect_to request.referer || citizens_verification_records_path,
                    notice: "✅ Address added successfully."
      else
        flash.now[:alert] = @address.errors.full_messages.to_sentence
        render partial: "citizens/profiles/address_fields",
               locals: { f: ActionView::Helpers::FormBuilder.new(:address, @address, self, {}) },
               status: :unprocessable_entity
      end
    end

    private

    def address_params
      params.require(:address).permit(
        :street_address,
        :locality,
        :postal_code,
        :country,
        :department_id,
        :arrondissement_id,
        :commune_id,
        :communal_section_id
      )
    end
  end
end
