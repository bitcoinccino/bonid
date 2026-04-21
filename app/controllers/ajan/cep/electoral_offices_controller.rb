# frozen_string_literal: true

# "Biwo mwen" — the BED/BEK this ajan belongs to. User→ElectoralOffice
# binding is selected at invite time (team/confirm.html.erb) but not yet
# persisted to a column on User; until that lands, this shows all offices
# for the partner's department.
module Ajan
  module Cep
    class ElectoralOfficesController < Ajan::ApplicationController
      def show
        @electoral_offices = ElectoralOffice.order(:office_type, :name).limit(50)
      end
    end
  end
end
