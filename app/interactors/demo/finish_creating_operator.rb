class Demo::FinishCreatingOperator
  include Interactor

  def call
    setup

    op = context.operator

    logo_path = logo_paths.shuffle.sample
    op.logo_image.attach(
      io: File.open(Rails.root.join("app/assets/images/logos/#{logo_path}")),
      filename: logo_path
    )

    background_path = background_paths.shuffle.sample
    op.background_image.attach(
      io: File.open(Rails.root.join("app/assets/images/backgrounds/#{background_path}")),
      filename: background_path
    )

    result = Demo::ReserveSubdomain.call(operator: op)
    if !result.success?
      context.fail!(message: "Error while creating operator: #{result.message}")
    end

    result = Demo::CreateAdmins.call(operator: op)
    if !result.success?
      context.fail!(message: "Error while creating admins: #{result.message}")
    end

    result = Demo::CreatePlans.call(operator: op)
    if !result.success?
      context.fail!(message: "Error while creating operator: #{result.message}")
    end

    result = Demo::CreateDayPassTypes.call(operator: op)
    if !result.success?
      context.fail!(message: "Error while creating operator: #{result.message}")
    end

    3.times do
      result = Demo::CreateRoom.call(operator: op)
      if !result.success?
        context.fail!(message: "Error creating room: #{result.message}")
      end
    end

    6.times do
      # Sometime in the last 60 days
      day = Time.current - rand(60).days

      result = Demo::CreateMember.call(operator: op, day: day)
      if !result.success?
        context.fail!(message: "Error creating members: #{result.message}")
      end
    end

    6.times do
      # Sometime in the next 30 days
      day = Time.current + rand(60).days

      result = Demo::CreateMember.call(operator: op, day: day)
      if !result.success?
        context.fail!(message: "Error creating members: #{result.message}")
      end
    end

    2.times do
      # Sometime in the last 30 days
      day = Time.current - rand(30).days

      result = Demo::CreateUnapprovedMember.call(operator: op, day: day)
      if !result.success?
        context.fail!(message: "Error creating unapproved members: #{result.message}")
      end
    end

    5.times do
      result = Demo::CreateDayPasser.call(operator: op)
      if !result.success?
        context.fail!(message: "Error creating day passers: #{result.message}")
      end
    end

    result = Demo::CreateFeedItems.call(operator: op)
    if !result.success?
      context.fail!(message: "Error creating feed items: #{result.message}")
    end

    op.doors.create!(name: "Front Door")

    OperatorMailer.new_demo_instance(context.user, op).deliver_later
    teardown
  end

  def logo_paths
    [1,2,3,4,5].map do |num|
      "#{num}.png"
    end
  end

  def background_paths
    [1,2,3,4,5,6,7,8,9,10,11,12].map do |num|
      "#{num}.jpg"
    end
  end

  def setup
    Stripe.api_key = Rails.configuration.stripe[:test_secret_key]
  end

  def teardown
    Stripe.api_key = Rails.configuration.stripe[:secret_key]
  end
end
