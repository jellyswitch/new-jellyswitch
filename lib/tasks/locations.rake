namespace :locations do
  desc "Backfill latitude/longitude on existing locations from their addresses"
  task backfill_geocoding: :environment do
    Location.where(latitude: nil).find_each do |loc|
      next if loc.building_address.blank?
      loc.geocode
      if loc.latitude && loc.longitude
        loc.save!
        puts "✓ #{loc.name}: #{loc.latitude}, #{loc.longitude}"
      else
        puts "✗ #{loc.name}: geocode failed"
      end
      sleep 1
    end
  end
end
