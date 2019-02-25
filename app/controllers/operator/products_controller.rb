class Operator::ProductsController < Operator::BaseController
  def index
    find_products
    authorize @products
    background_image
  end

  def show
    find_product
    authorize @product
    background_image
  end

  def edit
    find_product
    authorize @product
    background_image
  end

  def create
    @product = Product.new(product_params)
    authorize @product

    if @product.save
      flash[:notice] = "Product saved."
      redirect_to product_path(@product)
    else
      render :new
    end
  end

  def new
    @product = Product.new
    authorize @product
    background_image
  end

  def update
    find_product
    authorize @product

    @product.update_attributes(product_params)
    
    if @product.save
      flash[:notice] = "Product updated."
      redirect_to product_path(@product)
    else
      render :edit
    end
  end

  def destroy
    find_product
    authorize @product

    @product.update_attributes({available: false})
    if @product.save
      flash[:notice] = "Product archived."
      redirect_to products_path
    else
      flash[:error] = "Unable to archive product: #{@product.name}"
      redirect_to :back
    end
  end

  def unarchive
    find_product(:product_id)
    authorize @product
    result = UnarchiveProduct.call(product: @product)
    if result.success?
      flash[:success] = "Product unarchived."
    else
      flash[:error] = result.message
    end
    redirect_to product_path(@product)
  end

  private

  def find_products
    @products = Product.all
  end

  def find_product(key=:id)
    @product = Product.find(params[key])
  end

  def product_params
    params.require(:product).permit(:name, :price, :visible, :available)
  end
end