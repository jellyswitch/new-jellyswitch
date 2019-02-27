class CreateDayPassType
  include Interactor

  def call
    @day_pass_type = DayPassType.new(context.params)
    context.day_pass_type = @day_pass_type

    if !@day_pass_type.save
      context.fail!(message: "Couldn't save day pass type.")
    end

    if !@day_pass_type.operator.has_day_pass_product?
      context.fail!(message: "#{@day_pass_type.operator.name} has not set up a day pass product yet for this day pass type.")
    end

    stripe_sku = Stripe::SKU.create({
      product: @day_pass_type.operator.stripe_day_pass_product_id,
      currency: 'usd',
      price: @day_pass_type.amount_in_cents,
      inventory: { type: 'infinite' },
      attributes: { name: @day_pass_type.name }
    })

    @day_pass_type.stripe_sku_id = stripe_sku.id

    if !@day_pass_type.save
      context.fail!(message: "Couldn't update day pass type with stripe ID: #{stripe_sku.id}")
    end
  end
end