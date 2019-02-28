class Demo::CreateUnapprovedMember
  include Interactor
  include Demo::Avatars

  def call
    operator = context.operator
    day = context.day

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
        approved: false,
        out_of_band: true,
        created_at: day,
        updated_at: day
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