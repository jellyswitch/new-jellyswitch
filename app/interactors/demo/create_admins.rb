class Demo::CreateAdmins
  include Interactor
  include Demo::Avatars

  def call
    operator = context.operator

    2.times do
      name = Faker::Name.unique.name
      email = Faker::Internet.unique.safe_email
      password = "password"
      bio = Faker::GameOfThrones.quote
  
      result = CreateUser.call(
        params: {
          name: name, 
          email: email, 
          password: password,
          bio: bio,
          approved: true,
          out_of_band: true,
          admin: true,
          created_at: 40.days.ago,
          updated_at: 40.days.ago
        },
        operator: operator
      )
  
      if !result.success?
        context.fail!(message: result.message)
      end
  
      user = result.user
  
      path = avatar_ids.shuffle.sample
      user.profile_photo.attach(
        io: File.open(Rails.root.join("app/assets/images/avatars/#{path}")),
        filename: path
      )
  
    end
  end
end