# <!-- ================================
#  app/helpers/constellation_helper.rb
# =================================== -->

module ConstellationHelper
  def partner_nodes
    [
      # FINANCIAL INSTITUTIONS
      {
        name: "Unibank",
        logo: "partners/unibank.svg",
        sector: "bank"
      },
      {
        name: "Sogebank",
        logo: "partners/sogebank.svg",
        sector: "bank"
      },

      # TELECOMMUNICATIONS
      {
        name: "Digicel",
        logo: "partners/digicel.svg",
        sector: "telco"
      },

      # NON-GOVERNMENTAL ORGANIZATIONS
      {
        name: "FAES",
        logo: "partners/faes.svg",
        sector: "ngo"
      },

      # LAW ENFORCEMENT
      {
        name: "Police Nationale d'Haïti",
        logo: "partners/pnh.svg",
        sector: "law"
      },

      # GOVERNMENT & DIPLOMATIC
      {
        name: "U.S. Embassy",
        logo: "partners/us_embassy.svg",
        sector: "gov"
      },
      {
        name: "France Embassy",
        logo: "partners/france_embassy.svg",
        sector: "gov"
      }
    ]
  end

  def partner_sectors
    {
      bank: "Financial Services",
      telco: "Telecommunications",
      ngo: "Non-Governmental Organizations",
      law: "Law Enforcement",
      gov: "Government & Diplomatic"
    }
  end
end
