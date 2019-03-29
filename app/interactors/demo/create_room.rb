class Demo::CreateRoom
  include Interactor

  def call
    operator = context.operator

    room = Room.create!(
      name: Faker::Ancient.god,
      description: Faker::Company.catch_phrase,
      capacity: rand(1..5),
      whiteboard: [true, false].sample,
      av: [true, false].sample,
      operator_id: operator.id
    )

    path = room_photo_paths.shuffle.sample
    room.photo.attach(
      io: File.open(Rails.root.join("app/assets/images/rooms/#{path}")),
      filename: path
    )
    context.room = room
  end

  def room_photo_paths
    room_photos.map {|num| "#{num}.jpg" }
  end

  def room_photos
    [1,2,3,4,5]
  end
end