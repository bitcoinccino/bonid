# frozen_string_literal: true

# DgiRejectionReasons — Structured Rejection Codes for DGI Review
# ================================================================
# Haiti DGI structured rejection categories and codes.
# Used by DGI review controllers to provide standardized rejection
# reasons when returning citizen-filed declarations.
# ================================================================

module DgiRejectionReasons
  extend ActiveSupport::Concern

  # Rejection reason categories with codes and Creole descriptions
  REJECTION_CATEGORIES = {
    "ID" => {
      label: "Idantifikasyon & Done Pèsonèl",
      codes: {
        "ID-01" => "NIF/CIN envalid — Nimewo Idantifikasyon Fiskal oswa Kat Idantite Nasyonal pa koresponn ak dosye DGI.",
        "ID-02" => "Non pa koresponn — Non sou fòm lan pa menm ak non legal ki asosye ak NIF la.",
        "ID-03" => "Dokiman idantite ekspire — Dokiman idantite (Paspò, CIN, oswa Lisans) pa valab ankò."
      }
    },
    "DOC" => {
      label: "Dokimantasyon & Prèv",
      codes: {
        "DOC-01" => "Dokiman manke — Yon dokiman sipò obligatwa pa te telechaje.",
        "DOC-02" => "Skan pa lizib — Dokiman telechaje a pa klè oswa koupe.",
        "DOC-03" => "Siyati envalid — Fòm lan oswa dokiman sipò a pa gen siyati obligatwa."
      }
    },
    "FIN" => {
      label: "Finansye & Deklaratif",
      codes: {
        "FIN-01" => "Revni pa rapòte ase — Revni deklare pa konsistan ak sous revni yo.",
        "FIN-02" => "Erè aritmetik — Kalkil taks yo pa kòrèk matematitkman.",
        "FIN-03" => "Peryòd fiskal enkòrèk — Fòm lan te depoze pou yon ane oswa mwa ki deja regle."
      }
    },
    "ADM" => {
      label: "Konfòmite Administratif",
      codes: {
        "ADM-01" => "Dèt ki rete — Sitwayen an gen penalite oswa taks ki pa peye anvan.",
        "ADM-02" => "Jiridiksyon pa bon — Fòm lan te soumèt nan move biwo DGI lokal.",
        "ADM-03" => "Soumisyon doub — Yon deklarasyon pou menm tip taks ak peryòd deja ap trete."
      }
    },
    "TEC" => {
      label: "Teknik",
      codes: {
        "TEC-01" => "Fòma fichye pa sipòte — Fichye telechaje yo pa ranpli estanda sistèm nan.",
        "TEC-02" => "Fòm enkonplè — Youn oswa plizyè chan obligatwa te rete vid."
      }
    }
  }.freeze

  # Flat hash: code => reason text (for quick lookup)
  REJECTION_CODES = REJECTION_CATEGORIES.each_with_object({}) do |(_, cat), hash|
    cat[:codes].each { |code, reason| hash[code] = reason }
  end.freeze

  # Get the reason text for a given code
  def self.reason_for(code)
    REJECTION_CODES[code.to_s.upcase]
  end

  # Get the category label for a given code
  def self.category_for(code)
    prefix = code.to_s.split("-").first
    REJECTION_CATEGORIES.dig(prefix, :label)
  end
end
