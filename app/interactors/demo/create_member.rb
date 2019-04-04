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

    stripe_token = Stripe::Token.create({
      card: {
        number: '4242424242424242',
        exp_month: 3,
        exp_year: 2020,
        cvc: '314',
      },
    })

    stripe_customer = user.stripe_customer
    stripe_customer.source = stripe_token.id
    stripe_customer.save
    # Select a plan at random and subscribe them to it
    plan = operator.plans.available.all.shuffle.sample
    subscription = Subscription.new(
      plan_id: plan.id,
      user_id: user.id,
      active: true,
      created_at: day,
      updated_at: day
    )

    result = CreateSubscription.call(
      subscription: subscription,
      token: nil,
      user: user
    )

    if !result.success?
      context.fail!(message: "Error while creating subscription: #{result.message}")
    end
    subscription = result.subscription

    invoice_item = Stripe::InvoiceItem.create({
      customer: user.stripe_customer_id,
      currency: 'usd',
      amount: plan.amount_in_cents,
      description: plan.name,
    }, {
      api_key: user.operator.stripe_secret_key,
      stripe_account: user.operator.stripe_user_id
    })

    stripe_invoice = Stripe::Invoice.create({
      customer: user.stripe_customer_id
    },
    {
      api_key: user.operator.stripe_secret_key,
      stripe_account: user.operator.stripe_user_id
    })

    if day < Time.current
      stripe_invoice.finalize_invoice
      stripe_invoice.pay
      invoice = Invoice.create!(
        user_id: user.id,
        operator_id: user.operator.id,
        amount_due: subscription.plan.amount_in_cents.to_i,
        amount_paid: subscription.plan.amount_in_cents.to_i,
        number: rand(5000).to_i,
        stripe_invoice_id: stripe_invoice.id,
        date: day,
        due_date: day + 30.days,
        status: 'paid'
      )
    else
      # Create some 'open' and 'paid' invoices
      stripe_invoice.finalize_invoice
      if rand(10) < 5
        stripe_invoice.pay
      end

      invoice = Invoice.create!(
        user_id: user.id,
        operator_id: user.operator.id,
        amount_due: subscription.plan.amount_in_cents.to_i,
        amount_paid: stripe_invoice.amount_paid,
        number: rand(5000).to_i,
        stripe_invoice_id: stripe_invoice.id,
        date: day,
        due_date: day + 30.days,
        status: stripe_invoice.status
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
