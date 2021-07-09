# typed: false
# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

class FakeData
  def admins
    ["dpaola2@gmail.com"]
  end

  def user_photos
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 14, 15, 21, 24, 27, 37, 42, 44, 57, 60, 61, 71, 72, 77, 79, 81]
  end

  def room_photos
    [1, 2, 3, 4, 5]
  end

  def user_photo_paths
    user_photos.map { |num| "#{num}.jpg" }
  end

  def room_photo_paths
    room_photos.map { |num| "#{num}.jpg" }
  end

  def fake_user
    name = Faker::Name.unique.name
    email = Faker::Internet.unique.safe_email
    password = "password"
    bio = Faker::GreekPhilosophers.quote
    path = user_photo_paths.shuffle.sample

    user = User.create!(
      name: name,
      email: email,
      password: password,
      bio: bio,
      approved: true,
    )
    user.profile_photo.attach(
      io: File.open(Rails.root.join("app/assets/images/avatars/#{path}")),
      filename: path,
    )
    user
  end

  def fake_operator 
    name = Faker::Name.unique.name
    snippet = Faker::ChuckNorris.fact
    wifi_name = Faker::Artist.name
    wifi_password = "password"
    building_address = Faker::Address.street_address
    # approval_required = true
    subdomain = Faker::Internet.domain_name
    contact_name = Faker::Movies::Ghostbusters.character
    contact_email = Faker::Internet.email
    contact_phone = Faker::PhoneNumber.cell_phone
    background_image = Faker::Fillmurray.image
    logo_image = Faker::Company.logo
    square_footage = Faker::Number.number(digits: 4)
    # email_enabled = true 
    kisi_api_key = Faker::Internet.uuid
    # terms_of_service = Faker::Quotes::Shakespeare.hamlet_quote
    # push_notification_certificate = 
    ios_url = Faker::Internet.url
    android_url = Faker::Internet.url
    # checkin_required = true
    android_server_key = Faker::Internet.uuid

    operator = Operator.create!(
      name: name,
      snippet: snippet,
      wifi_name: wifi_name,
      wifi_password: wifi_password,
      building_address: building_address,
      approval_required: true,
      subdomain: subdomain,
      contact_name: contact_name,
      contact_email: contact_email,
      contact_phone: contact_phone,
      background_image: background_image,
      logo_image: logo_image,
      square_footage: square_footage,
      email_enabled: true,
      kisi_api_key: kisi_api_key,
      ios_url: ios_url,
      android_url: android_url,
      checkin_required: true,
      android_server_key: android_server_key,
    )
    operator
  end

  def fake_org
    name = Faker::Company.unique.name
    owner = fake_user
    operator = fake_operator
    website = Faker::Internet.url

    org = Organization.create!(
      name: name,
      owner: owner,
      operator: operator,
      website: website,
    )
    org
  end

  def fake_room
    room = Room.create!(
      name: Faker::Ancient.unique.god,
      description: Faker::Company.catch_phrase,
      capacity: rand(1..5),
      whiteboard: [true, false].sample,
      av: [true, false].sample,
      location_id: 1,
    )

    path = room_photo_paths.shuffle.sample # "2.jpg"
    room.photo.attach(
      io: File.open(Rails.root.join("app/assets/images/rooms/#{path}")),
      filename: path,
    )
    room
  end

  def fake_plans
    Plan.create!(interval: "monthly", amount_in_cents: 0, name: "Free membership", visible: false)
    Plan.create!(interval: "monthly", amount_in_cents: 16000, name: "Part-time Membership")
    Plan.create!(interval: "monthly", amount_in_cents: 35000, name: "Full-time Membership")
    Plan.create!(interval: "monthly", amount_in_cents: 50000, name: "Full time office membership")
  end

  def fake_doors
    Door.create!(name: "Front Door")
    Door.create!(name: "Back Door")
  end

  def run
    fake_doors
    fake_plans
    fake_operator
    ActiveRecord::Base.transaction do
      admins.each do |email|
        admin = User.create!(
          name: "Dave Paola",
          email: email,
          password: "pizza123",
          admin: true,
          bio: Faker::GreekPhilosophers.quote,
          approved: true,
        )
        admin.profile_photo.attach(
          io: File.open(Rails.root.join("app/assets/images/avatars/dave.png")),
          filename: "dave.png",
        )
      end

      25.times do
        puts fake_user.name
      end

      3.times do
        org = fake_org
        3.times do
          org.users << fake_user
        end
        puts org.name
      end

      5.times do
        room = fake_room
        puts room.name
      end
    end
  end
end

f = FakeData.new
ApplicationRecord.transaction do
  f.run()
end
