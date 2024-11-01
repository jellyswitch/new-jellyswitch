namespace :migrations do
  desc "Update location data for existing entities"
  task update_location_data: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      main_location = operator.locations.order(:id).first
      if main_location
        p "Using location #{main_location.name}"

        [:announcements, :day_passes, :member_feedbacks, :feed_items, :weekly_updates].each do |resource|
            p "Updating location for #{resource}"
            operator.send(resource).where(location_id: nil).update_all(location_id: main_location.id)
        end

        p "Updating location for users"
        operator.users.update_all(original_location_id: main_location.id, current_location_id: main_location.id)
      end
    end
  end

  desc "Update kisi api key for locations"
  task update_kisi_api_key: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      p "Updating kisi api key for locations without a key"
      operator.locations.where(kisi_api_key: nil).update_all(kisi_api_key: operator.kisi_api_key)
    end
  end

  desc "Update location for organizations"
  task update_organization_location: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      main_location = operator.locations.order(:id).first
      p "Updating location for organizations"
      operator.organizations.where(location_id: nil).update(location_id: main_location.id) if main_location
    end
  end
end
