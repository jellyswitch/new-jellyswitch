class Demo::CreateOperator
  include Interactor

  def call
    op = Operator.new
    op.name = Faker::Company.unique.name
    op.snippet = Faker::GameOfThrones.quote
    op.wifi_name = op.name
    op.wifi_password = Faker::Ancient.unique.god
    op.building_address = Faker::Address.full_address
    op.approval_required = true
    op.subdomain = op.name.parameterize
    op.contact_name = Faker::Name.unique.name
    op.contact_email = Faker::Internet.unique.safe_email
    op.contact_phone = Faker::PhoneNumber.phone_number
    op.square_footage = 5000
    op.email_enabled = false
    # TODO: background_image and logo_image

    context.operator = op

    if !op.save
      context.fail!(message: "Unable to create operator.")
    end
  end
end