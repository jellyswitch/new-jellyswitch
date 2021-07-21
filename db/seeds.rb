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
    ["mi.shelbyrose@gmail.com"]
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

  def fake_user(operator)
    name = Faker::Name.unique.name
    email = Faker::Internet.unique.safe_email
    password = "password"
    bio = Faker::Hipster.sentence
    path = user_photo_paths.shuffle.sample

    User.create!(
      operator: operator,
      name: name,
      email: email,
      password: password,
      bio: bio,
      approved: true,
    )
    # user.profile_photo.attach(
    #   io: File.open(Rails.root.join("app/assets/images/avatars/#{path}")),
    #   filename: path,
    # )
    
  end

  def fake_operator
    name = Faker::FunnyName.name
    snippet = Faker::ChuckNorris.fact
    wifi_name = Faker::Hobby.activity
    wifi_password = Faker::Cannabis.cannabinoid
    building_address = Faker::Address.full_address
    subdomain = Faker::Beer.brand.downcase
    contact_name = Faker::FunnyName.name
    contact_email = Faker::Internet.email
    contact_phone = Faker::PhoneNumber.phone_number
    # background_image = Faker::CryptoCoin.url_logo
    # logo_image = Faker::Fillmurray.image(grayscale: true)
    square_footage =  Faker::Number.decimal(l_digits: 2, r_digits: 1)
    # kisi_api_key = Faker::Barcode.ean(8)
    # terms_of_service = Faker::Coffee.notes,
    # push_notification_certificate = Faker::Number.decimal(l_digits: 3, r_digits: 3),
    # ios_url = Faker::Internet.url
    # android_url = Faker::Internet.url
    # android_server_key = Faker::Hobby.activity

    Operator.create!(
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
      # background_image: background_image, 
      # logo_image: logo_image, 
      square_footage: square_footage, 
      email_enabled: true, 
      # kisi_api_key: kisi_api_key, 
      # terms_of_service: terms_of_service,
      # push_notification_certificate: push_notification_certificate, 
      # ios_url: ios_url, 
      # android_url: android_url, 
      checkin_required: true,
      # android_server_key: android_server_key 
    )
  end

  def fake_org(operator)
    name = Faker::Company.unique.name
    owner = fake_user(operator)
    website = Faker::Internet.url

    Organization.create!(
      name: name,
      owner: owner,
      website: website,
      operator: operator
    )
  end

  def fake_room(operator)
    room = Room.create!(
      operator: operator,
      name: Faker::Ancient.unique.god,
      description: Faker::Company.catch_phrase,
      capacity: rand(1..5),
      whiteboard: [true, false].sample,
      av: [true, false].sample,
      location_id: 1,
    )

    path = room_photo_paths.shuffle.sample # "2.jpg"
    # room.photo.attach(
    #   io: File.open(Rails.root.join("app/assets/images/rooms/#{path}")),
    #   filename: path,
    # )
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
    # fake_doors
    # fake_plans
    first_coworking_space = fake_operator
    ActiveRecord::Base.transaction do
      admins.each do |email|
        admin = User.create!(
          operator: first_coworking_space,
          name: "Aliens",
          email: email,
          password: "pizza123",
          admin: true,
          bio: "", #Faker::Company.catch_phrase,
          approved: true,
        )
        # admin.profile_photo.attach(
        #   io: File.open(Rails.root.join("app/assets/images/avatars/dave.png")),
        #   filename: "dave.png",
        # )
      end

      25.times do
        puts fake_user(first_coworking_space).name
      end

      3.times do
        org = fake_org(first_coworking_space)
        3.times do
          org.users << fake_user(first_coworking_space)
        end
        puts org.name
      end

      5.times do
        room = fake_room(first_coworking_space)
        puts room.name
      end
    end
  end
end

f = FakeData.new
ApplicationRecord.transaction do
  f.run()
end