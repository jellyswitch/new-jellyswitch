module AccountingHelper
  def expenses_from_month
    @expenses = current_tenant.feed_items.where("extract(month from created_at) = ? and expense = ? ", params[:month], true)
  end

  def revenue_from_month
    @revenue = current_tenant.invoices.paid.this_month.sum(:amount_due).to_f / 100.0
  end
end