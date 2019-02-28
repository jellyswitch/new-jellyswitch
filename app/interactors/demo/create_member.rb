class Demo::CreateMember
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
        approved: true,
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

    # Select a plan at random and subscribe them to it
    plan = operator.plans.available.all.shuffle.sample
    subscription = Subscription.create!(
      plan_id: plan.id,
      user_id: user.id,
      active: true,
      created_at: day,
      updated_at: day
    )

    if day < Time.current
      invoice = Invoice.create!(
        user_id: user.id,
        operator_id: user.operator.id,
        amount_due: subscription.plan.amount_in_cents.to_i,
        amount_paid: subscription.plan.amount_in_cents.to_i,
        number: rand(5000).to_i,
        stripe_invoice_id: nil,
        date: day,
        due_date: day + 30.days,
        status: "paid"
      )
    else
      invoice = Invoice.create!(
        user_id: user.id,
        operator_id: user.operator.id,
        amount_due: subscription.plan.amount_in_cents.to_i,
        amount_paid: 0,
        number: rand(5000).to_i,
        stripe_invoice_id: nil,
        date: day,
        due_date: day + 30.days,
        status: "open"
      )
    end

    if rand(10) < 5
      room = operator.rooms.sample
      result = CreateRoomReservation.call(
        reservation_params: {
          user_id: user.id,
          datetime_in: day + rand(4).days,
          hours: rand(3),
          room_id: room.id,
          created_at: day
        },
        user: user
      )
    end

    if rand(10) < 4
      result = CreateMemberFeedback.call(
        member_feedback_params: {
          anonymous: false,
          user_id: user.id,
          comment: Faker::Company.bs,
          created_at: day,
          updated_at: day
        },
        operator: operator,
        user: user
      )
      if !result.success?
        context.fail!(message: "Error creating member feedback: #{result.message}")
      end
    end
  end
end