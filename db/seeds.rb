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
  def photos
    [0,1,2,3,4,5,6,7,8,14,15,21,24,27,37,42,44,57,60,61,71,72,77,79,81]
  end

  def photo_paths
    photos.map {|num| "#{num}.jpg" }
  end

  def fake_user
    name = Faker::Name.name
    email = Faker::Internet.safe_email
    password = "password"
    bio = Faker::GameOfThrones.quote
    path = photo_paths.shuffle.sample


    user = User.create!(
      name: name, 
      email: email, 
      password: password,
      bio: bio
    )
    user.profile_photo.attach(
      io: File.open(Rails.root.join("app/assets/images/avatars/#{path}")),
      filename: path
    )
    user
  end

  def fake_org
    name = Faker::Company.name
    owner = fake_user
    website = Faker::Internet.url

    Organization.create!(
      name: name,
      owner: owner,
      website: website
    )
  end

  def fake_room
    Room.create!(
      name: Faker::Ancient.god,
      description: Faker::Company.catch_phrase,
      capacity: rand(1..5),
      whiteboard: true
    )
  end

  def fake_plans
    Plan.create!(interval: "monthly", amount_in_cents: 0, name: "Free membership")
    Plan.create!(interval: "once", amount_in_cents: 3500, name: "Day Pass")
    Plan.create!(interval: "monthly", amount_in_cents: 16000, name: "Part-time Membership")
    Plan.create!(interval: "monthly", amount_in_cents: 35000, name: "Full-time Membership")
    Plan.create!(interval: "monthly", amount_in_cents: 50000, name: "Full time office membership")
  end

  def run
    ActiveRecord::Base.transaction do
      admins.each do |email|
        admin = User.create!(
          name: "Dave Paola",
          email: email,
          password: "pizza123",
          admin: true,
          bio: Faker::GameOfThrones.quote
        )
        admin.profile_photo.attach(
          io: File.open(Rails.root.join("app/assets/images/avatars/dave.png")),
          filename: "dave.png"
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

      fake_plans
    end
  end
end
f = FakeData.new
f.run()