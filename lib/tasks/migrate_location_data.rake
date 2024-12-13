namespace :migrations do
  desc "Update location data for existing entities"
  task update_location_data: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      main_location = operator.locations.order(:id).first
      if main_location
        p "Using location #{main_location.name}"

        [:announcements, :day_passes, :member_feedbacks, :feed_items, :weekly_updates, :day_pass_types].each do |resource|
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

  desc "Migrate plans and invoices to locations"
  task migrate_plans_and_invoices: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      main_location = operator.locations.order(:id).first
      p "Migrating plans"
      operator.plans.where(location_id: nil).update_all(location_id: main_location.id) if main_location
      p "Migrating plan categories"
      operator.plan_categories.where(location_id: nil).update_all(location_id: main_location.id) if main_location
      p "Migrating invoices"
      operator.invoices.where(location_id: nil).update_all(location_id: main_location.id) if main_location
    end
  end

  desc "Migrate stripe keys to locations"
  task migrate_stripe_keys: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      p "Migrating stripe keys"
      operator.locations.where(stripe_access_token: nil).update_all(stripe_access_token: operator.stripe_access_token)
      operator.locations.where(stripe_publishable_key: nil).update_all(stripe_publishable_key: operator.stripe_publishable_key)
      operator.locations.where(stripe_refresh_token: nil).update_all(stripe_refresh_token: operator.stripe_refresh_token)
      operator.locations.where(stripe_user_id: nil).update_all(stripe_user_id: operator.stripe_user_id)
    end
  end

  desc "Migrate enabled modules to locations"
  task migrate_module_enabled: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      p "Migrating enabled modules"
      operator.locations.update_all(announcements_enabled: operator.announcements_enabled)
      operator.locations.update_all(events_enabled: operator.events_enabled)
      operator.locations.update_all(door_integration_enabled: operator.door_integration_enabled)
      operator.locations.update_all(rooms_enabled: operator.rooms_enabled)
      operator.locations.update_all(offices_enabled: operator.offices_enabled)
      operator.locations.update_all(bulletin_board_enabled: operator.bulletin_board_enabled)
      operator.locations.update_all(credits_enabled: operator.credits_enabled)
      operator.locations.update_all(childcare_enabled: operator.childcare_enabled)
      operator.locations.update_all(crm_enabled: operator.crm_enabled)
    end
  end

  desc "Set location managers"
  task set_location_managers: :environment do
    Operator.all.each do |operator|
      p "Processing operator #{operator.name}"
      main_location = operator.locations.order(:id).first
      p "Setting managed locations for admins"
      operator.users.admins.each do |admin|
        admin.update(managed_location_ids: [main_location.id])
      end

      p "Setting managed locations for general managers"
      operator.users.general_managers.each do |gm|
        gm.update(managed_location_ids: [main_location.id])
      end

      p "Setting managed locations for community managers"
      operator.users.community_managers.each do |cm|
        cm.update(managed_location_ids: [main_location.id])
      end
    end
  end

  desc "Create user payment profiles for existing users"
  task create_user_payment_profiles: :environment do
    Location.find_each do |location|
      p "Processing location ##{location.id} - #{location.name}"
      location.users.find_each do |user|
        p "Processing user ##{user.id} - #{user.name}"
        payment_profile = user.user_payment_profiles.new(location_id: location.id)
        payment_profile.stripe_customer_id = user.stripe_customer_id
        payment_profile.card_added = user.card_added
        payment_profile.save
      end
    end
  end
end
