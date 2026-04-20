# frozen_string_literal: true

# Citizens::Election::OfficesController
#
# Locator page: "Where can I go for in-person help with voter registration?"
#
# Ranking:
#   1. BEK in the citizen's commune (closest tier)
#   2. BED in the citizen's department (fallback)
#   3. Open offices before planned ones
#   4. Ordered by `priority`, then name
module Citizens
  module Election
    class OfficesController < BaseController
      def index
        dept_id    = current_citizen.address&.department_id
        commune_id = current_citizen.address&.commune_id

        @bek_offices = ElectoralOffice.bek
                                      .for_commune(commune_id)
                                      .includes(:address, :commune)
                                      .ordered
                                      .to_a if commune_id

        @bed_offices = ElectoralOffice.bed
                                      .for_department(dept_id)
                                      .includes(:address, :department)
                                      .ordered
                                      .to_a if dept_id

        @bek_offices ||= []
        @bed_offices ||= []

        # If neither scope matched (new or missing address), fall back to
        # all open offices so the citizen still sees something actionable.
        @fallback_offices = if @bek_offices.empty? && @bed_offices.empty?
                              ElectoralOffice.open.ordered.limit(10).to_a
        else
                              []
        end
      end
    end
  end
end
