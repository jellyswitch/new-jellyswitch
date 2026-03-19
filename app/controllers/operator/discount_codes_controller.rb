class Operator::DiscountCodesController < Operator::BaseController
  before_action :find_discount_code, only: [:show, :edit, :update, :destroy]

  def index
    @discount_codes = DiscountCode.for_location(current_location).order(created_at: :desc)
    authorize @discount_codes
  end

  def show
    authorize @discount_code
  end

  def new
    @discount_code = DiscountCode.new
    authorize @discount_code
  end

  def edit
    authorize @discount_code
  end

  def create
    @discount_code = DiscountCode.new(discount_code_params)
    @discount_code.location = current_location
    authorize @discount_code

    if @discount_code.save
      flash[:success] = "Discount code created successfully."
      turbo_redirect(discount_codes_path)
    else
      render :new, status: 422
    end
  rescue StandardError => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(discount_codes_path)
  end

  def update
    authorize @discount_code

    if @discount_code.update(discount_code_params)
      flash[:success] = "Discount code updated successfully."
      turbo_redirect(discount_codes_path)
    else
      render :edit, status: 422
    end
  rescue StandardError => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(discount_codes_path)
  end

  def destroy
    authorize @discount_code
    @discount_code.update(active: false)
    flash[:success] = "Discount code deactivated."
    turbo_redirect(discount_codes_path)
  end

  private

  def find_discount_code
    @discount_code = DiscountCode.find(params[:id])
  end

  def discount_code_params
    params.require(:discount_code).permit(
      :code, :discount_type, :discount_value, :applies_to,
      :max_redemptions, :expires_at, :active
    ).tap do |p|
      # Convert dollar amount to cents if amount_off
      if p[:discount_type] == "amount_off" && p[:discount_value].present?
        p[:discount_value] = (p[:discount_value].to_f * 100).round
      end
    end
  end
end
