class Demo::CreateAdmin
  include Interactor

  def call
    operator = context.operator

    admin = User.new
    admin.admin = true
    admin.operator_id = operator.id
    admin.name = Faker::Name.unique.name
    admin.email = Faker::Internet.unique.safe_email
    admin.password = "password"
    admin.approved = true

    context.admin = admin

    if !admin.save
      context.fail!(message: "Unable to save admin user.")
    end

    result = CreateStripeCustomer.call(user: admin)
    
    if !result.success?
      context.fail!(message: "Error while creating admin user: #{result.message}")
    end
  end
end