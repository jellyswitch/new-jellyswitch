
class Operator::AccountingController < Operator::BaseController
  # feed_items has NO amount column — an expense's amount lives in
  # blob['amount'] as integer cents (FeedItem#parse_amount). Summing the
  # jsonb field needs a cast, and the cast needs a guard: one legacy blob
  # holding a non-numeric string would 500 the whole page.
  EXPENSE_CENTS_SQL = Arel.sql(
    "CASE WHEN blob->>'amount' ~ '^-?[0-9]+(\\.[0-9]+)?$' " \
    "THEN (blob->>'amount')::numeric ELSE 0 END"
  ).freeze

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
    expenses_scope = FeedItem.for_operator(current_tenant).for_location(current_location).expenses.order("created_at DESC")
    @expenses_total = expenses_scope.sum(EXPENSE_CENTS_SQL)
    @pagy, @expenses = pagy(expenses_scope)
  end

  def update_expenses
    @expenses = FeedItem.for_operator(current_tenant).for_location(current_location).where("extract(month from created_at) = ? and expense = ? ", params[:month], true)
  end
end
