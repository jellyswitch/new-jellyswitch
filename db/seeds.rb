# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

admins = ["dpaola2@gmail.com"]
members = ["alice@foo.com", "bob@foo.com", "curtis@foo.com", "dave@foo.com"]

admins.each do |email|
  User.create! email: email, password: "password", admin: true
end

members.each do |email|
  User.create! email: email, password: "password"
end
