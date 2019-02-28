class Demo::CreateMember
  include Interactor

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

    # Select a plan at random and subscribe them to it
    plan = operator.plans.available.all.shuffle.sample
    subscription = Subscription.new(
      plan_id: plan.id,
      user_id: user.id,
      active: true
    )
    result = CreateSubscription.call(subscription: subscription, user: user)
    if !result.success?
      context.fail!(message: "Error creating member subscription: #{result.message}")
    end

  end

  def avatar_ids
    [0,1,2,3,4,5,6,7,8,14,15,21,24,27,37,42,44,57,60,61,71,72,77,79,81].map do |num|
      "#{num}.jpg"
    end
  end
end