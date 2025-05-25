require 'csv'

puts "🚨 Cleaning up old data..."
Address.destroy_all
CommunalSection.destroy_all
Commune.destroy_all
Arrondissement.destroy_all
Department.destroy_all

puts "📦 Seeding Departments..."
CSV.foreach(Rails.root.join('db/data/departments.csv'), headers: true) do |row|
  Department.create!(
    id: row['id'].to_i,
    name: row['department_name'],
    postal_code_prefix: row['postal_code_prefix']
  )
end
puts "✅ Departments seeded: #{Department.count} records"

puts "📦 Seeding Arrondissements..."
CSV.foreach(Rails.root.join('db/data/arrondissements.csv'), headers: true) do |row|
  Arrondissement.create!(
    id: row['id'].to_i,
    name: row['arrondissement_name'],
    department_id: row['department_id'].to_i,
    code: row['postal_code_prefix']
  )
end
puts "✅ Arrondissements seeded: #{Arrondissement.count} records"

# 🔧 Create arrondissement → department mapping
department_id_lookup = Arrondissement.all.index_by(&:id).transform_values(&:department_id)


puts "📦 Seeding Communes..."
CSV.foreach(Rails.root.join('db/data/communes.csv'), headers: true) do |row|
  arrondissement_id = row['arrondissement_id'].to_i
  Commune.create!(
    id: row['id'].to_i,                      # Integer (1–140)
    code: row['commune_id'],                 # String code (e.g., HT0111)
    name: row['commune_name'],
    arrondissement_id: arrondissement_id,
    postal_code: row['postal_code_prefix'],
    department_id: department_id_lookup[arrondissement_id]
  )
end

puts "✅ Communes seeded: #{Commune.count} records"

puts "📦 Seeding Communal Sections..."
# 🔁 Create a mapping from commune code (HT0111) to numeric ID (1–140)
commune_code_to_id = Commune.all.index_by(&:code).transform_values(&:id)

puts "📦 Seeding Communal Sections..."
CSV.foreach(Rails.root.join('db/data/communal_sections.csv'), headers: true) do |row|
  next if row['postal_code'].blank? || row['commune_id'].blank?

  commune_id = commune_code_to_id[row['commune_id']]
  next unless commune_id # skip if the commune code doesn't match

  CommunalSection.create!(
    id: row['id'].to_i,
    name: row['section_name'],
    commune_id: commune_id,
    postal_code: row['postal_code']
  )
end

puts "✅ Communal Sections seeded: #{CommunalSection.count} records"

puts "✅ Seeding complete!"