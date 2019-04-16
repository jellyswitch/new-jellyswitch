class AddLocationAndResourcesForSpaces < ActiveRecord::Migration[5.2]
  def up
    operator = Operator.find_by subdomain: 'demo2'

    location = operator.locations.create!(
      operator.attributes.except(*%w(
        id
        android_url
        approval_required
        day_pass_cost_in_cents
        email_enabled
        ios_url
        kisi_api_key
        subdomain
        created_at
        updated_at
        stripe_user_id
      )
    ).merge(city: 'South Lake Tahoe', state: 'CA', zip: '96150'))

    operator.locations.create!(
      building_address: '110 Sutter St',
      city: 'San Francisco',
      state: 'CA',
      zip: '94104',
      wifi_name: 'wifi',
      wifi_password: 'wifi',
      square_footage: 2000,
      name: 'BlocWork',
      contact_email: 'loree.smith@example.net'
    )

    %w(rooms offices office_leases member_feedbacks feed_items doors).each do |resource|
      add_reference :"#{resource}", :location, foreign_key: true

      resource.camelize.singularize.constantize.reset_column_information

      operator.public_send(resource).each do |model|
        model.location_id = location.id
        model.save!
      end
    end
  end

  def down
    %w(rooms offices office_leases member_feedbacks feed_items doors).each do |resource|
      remove_reference :"#{resource}", :location, foreign_key: true
    end
    Location.delete_all
  end
end
