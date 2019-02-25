class UnarchiveProduct
  include Interactor

  def call
    @product = context.product
    validate
    @product.available = true
    if !@product.save
      context.fail!(message: "Failed to save product.")
    end
  end

  def validate
    if @product.available?
      context.fail!(message: "Cannot unarchive a product that's already available.")
    end
  end
end
