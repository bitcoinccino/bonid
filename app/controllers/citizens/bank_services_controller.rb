# app/controllers/citizens/bank_services_controller.rb
module Citizens
  class BankServicesController < Citizens::BaseController
    def index
      @verified = current_citizen&.identity_submissions&.approved&.exists?

      @banks = [
        {
          name: "Unibank",
          slug: "unibank",
          icon: "ri-bank-fill",
          color: "#00209F",
          description: "Pi gwo bank komèsyal an Ayiti. Kont epay, kont kouran, ak sèvis anliy.",
          services: ["Kont Epay", "Kont Kouran", "Kat Debi"],
          status: :coming_soon
        },
        {
          name: "Sogebank",
          slug: "sogebank",
          icon: "ri-bank-fill",
          color: "#006B3F",
          description: "Bank ki ofri sèvis konplè pou endividi ak antrepriz.",
          services: ["Kont Epay", "Kont Kouran", "Prè Pèsonèl"],
          status: :coming_soon
        },
        {
          name: "BNC",
          slug: "bnc",
          icon: "ri-government-fill",
          color: "#C8102E",
          description: "Bank Nasyonal de Kredi — bank leta ki sipòte devlopman ekonomik.",
          services: ["Kont Epay", "Kont Kouran", "Prè Agrikòl"],
          status: :coming_soon
        }
      ]
    end
  end
end
