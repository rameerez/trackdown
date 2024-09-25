namespace :trackdown do
  desc "Update MaxMind GeoLite2 City database"
  task update_database: :environment do
    Trackdown.update_database
  end
end
