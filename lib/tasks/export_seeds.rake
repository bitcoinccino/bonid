# Production rake task to export Departments, Arrondissements, Communes, and Communal Sections to CSV files.
namespace :export_seeds do
  desc "Export Departments, Arrondissements, Communes, and Communal Sections to CSV"
  task export: :environment do
    require "csv"

    puts "Exporting Departments..."
    CSV.open("db/csv/departments.csv", "w") do |csv|
      csv << ["id", "name"]
      Department.all.find_each do |d|
        csv << [d.id, d.name]
      end
    end

    puts "Exporting Arrondissements..."
    CSV.open("db/csv/arrondissements.csv", "w") do |csv|
      csv << ["id", "name", "postal_code_digit", "department_name"]
      Arrondissement.includes(:department).find_each do |a|
        csv << [a.id, a.name, a.postal_code_digit, a.department.name]
      end
    end

    puts "Exporting Communes..."
    CSV.open("db/csv/communes.csv", "w") do |csv|
      csv << ["id", "name", "postal_code_digit", "arrondissement_name"]
      Commune.includes(:arrondissement).find_each do |c|
        csv << [c.id, c.name, c.postal_code_digit, c.arrondissement.name]
      end
    end

    puts "Exporting Communal Sections..."
    CSV.open("db/csv/communal_sections.csv", "w") do |csv|
      csv << ["id", "name", "postal_code_digit", "commune_name"]
      CommunalSection.includes(:commune).find_each do |cs|
        csv << [cs.id, cs.name, cs.postal_code_digit, cs.commune.name]
      end
    end

    puts "✅ Export complete! Files saved in db/csv/"
  end
end

