# app/controllers/citizens/bill_payments_controller.rb
module Citizens
  class BillPaymentsController < Citizens::BaseController
    def index
      @verified = current_citizen&.identity_submissions&.approved&.exists?

      @providers = [
        {
          name: "EDH",
          full_name: "Elektrisite d Ayiti",
          slug: "edh",
          icon: "ri-flashlight-fill",
          color: "#F59E0B",
          category: :electricity,
          description: "Peye fakti elektrisite ou anliy — san fè liy.",
          status: :coming_soon
        },
        {
          name: "DINEPA",
          full_name: "Direksyon Nasyonal Dlo Potab",
          slug: "dinepa",
          icon: "ri-drop-fill",
          color: "#3B82F6",
          category: :water,
          description: "Peye fakti dlo ou — jere kont dlo ou fasil.",
          status: :coming_soon
        }
      ]
    end
  end
end
