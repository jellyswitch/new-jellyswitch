# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

admins = ["dpaola2@gmail.com"]

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
