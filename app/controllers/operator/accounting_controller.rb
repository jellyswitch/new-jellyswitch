
class Operator::AccountingController < Operator::BaseController
  def index
    background_image

    # Use for_location to include invoices with NULL location_id (e.g. office leases from webhooks)
    invoices = Invoice.for_location(current_location)

    @last_month_revenue = invoices.last_month.sum(:amount_due)
    sq_ft = current_location.square_footage.to_f
    @last_month_square_footage = sq_ft > 0 ? (@last_month_revenue.to_f / 100.0) / sq_ft : 0

    @this_month_revenue = invoices.this_month.sum(:amount_due)
    @this_month_square_footage = sq_ft > 0 ? (@this_month_revenue.to_f / 100.0) / sq_ft : 0
  end

  def expenses
    background_image
    expenses_scope = FeedItem.for_operator(current_tenant).expenses.order("created_at DESC")
    @expenses_total = expenses_scope.sum(:amount)
    @pagy, @expenses = pagy(expenses_scope)
  end

  def update_expenses
    @expenses = FeedItem.where("extract(month from created_at) = ? and expense = ? ", params[:month], true)
  end
end
