class Demo::CreateOperator
  include Interactor

  def call
    op = Operator.new
    op.name = Faker::Company.unique.name
    op.snippet = Faker::GameOfThrones.quote
    op.wifi_name = op.name
    op.wifi_password = Faker::Ancient.god
    op.building_address = Faker::Address.full_address
    op.contact_name = Faker::Name.unique.name
    op.contact_email = Faker::Internet.unique.safe_email
    op.contact_phone = Faker::PhoneNumber.phone_number
    op.square_footage = 2000
    op.subdomain = "placeholder"
    op.stripe_user_id = ENV['STRIPE_ACCOUNT_ID']
    op.stripe_publishable_key = nil
    op.stripe_refresh_token = nil
    op.stripe_access_token = nil

    context.operator = op

    if !op.save
      context.fail!(message: "Unable to create operator.")
    end

    CreateOperatorJob.perform_later(op, context.user)
  end
end