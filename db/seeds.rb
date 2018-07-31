# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

admins = ["dpaola2@gmail.com"]

def fake_user
  name = Faker::Name.name
  email = Faker::Internet.safe_email
  password = "password"
  bio = Faker::GameOfThrones.quote

  User.create!(
    name: name, 
    email: email, 
    password: password,
    bio: bio
  )
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

admins.each do |email|
  User.create!(
    name: "Dave Paola",
    email: email,
    password: "pizza123",
    admin: true,
    bio: Faker::GameOfThrones.quote
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