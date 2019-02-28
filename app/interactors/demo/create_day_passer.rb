class Demo::CreateDayPasser
  include Interactor
  include Demo::Avatars

  def call
    operator = context.operator

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
        out_of_band: true
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

    day_pass_type_id = operator.day_pass_types.available.visible.first.id
    day = Time.current

    result = CreateDayPass.call(
      params: {
        day_pass_type: day_pass_type_id,
        day: day,
        operator_id: operator.id
      },
      operator: operator,
      user_id: user.id
    )

    if !result.success?
      context.fail!(message: result.message)
    end
  end
end