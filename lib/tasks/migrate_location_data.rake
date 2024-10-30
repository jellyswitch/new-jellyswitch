namespace :migrations do
    desc "Update location data for existing entities"
    task update_location_data: :environment do
      Operator.all.each do |operator|
        main_location = operator.locations.order(:id).first

        [:announcements, :day_passes, :member_feedbacks, :feed_items, :weekly_updates].each do |resource|
            operator.send(resource).where(location_id: nil).update_all(location_id: main_location.id)
        end
      end
    end
  end
