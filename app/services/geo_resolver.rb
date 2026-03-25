# app/services/geo_resolver.rb
class GeoResolver
  def self.resolve(address)
    return address unless address.present?

    if address.communal_section_id.present?
      section = CommunalSection.includes(commune: { arrondissement: :department }).find_by(id: address.communal_section_id)
      if section
        address.commune_id ||= section.commune_id
        address.arrondissement_id ||= section.commune.arrondissement_id
        address.department_id ||= section.commune.arrondissement.department_id
      end
    elsif address.commune_id.present?
      commune = Commune.includes(arrondissement: :department).find_by(id: address.commune_id)
      if commune
        address.arrondissement_id ||= commune.arrondissement_id
        address.department_id ||= commune.arrondissement.department_id
      end
    end

    address
  end
end
