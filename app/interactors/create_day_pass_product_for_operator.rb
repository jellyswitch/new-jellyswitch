class CreateDayPassProductForOperator
  include Interactor

  def call
    @operator = context.operator

    product_name = "#{@operator.name} - Day Pass Product"
    description = "Day pass for #{@operator.name}"

    stripe_product = Stripe::Product.create({
      name: product_name,
      type: 'good',
      description: description,
      attributes: ["name"]
    })

    @operator.stripe_day_pass_product_id = stripe_product.id

    if !@operator.save
      context.fail!(message: "Could not update operator with product ID: #{stripe_product.id}")
    end
  end
end