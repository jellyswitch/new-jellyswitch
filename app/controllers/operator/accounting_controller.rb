class Operator::AccountingController < Operator::BaseController
  def index
    background_image

    @last_month_start = (Date.today.beginning_of_month - 1.day).beginning_of_month.to_time.to_i
    @this_month_start = Date.today.beginning_of_month.to_time.to_i

    @members = current_tenant.plans.includes(:subscriptions).map(&:subscriptions).flatten.map(&:user).uniq
    @invoices = @members.map(&:invoices).map(&:data).flatten.select {|i| i.paid == true}
    
    @last_month_invoices = @invoices.select do |invoice|
      invoice.date > @last_month_start && invoice.date < @this_month_start
    end

    @last_month_revenue = @last_month_invoices.sum{|invoice| invoice.amount_paid }
    @last_month_square_footage = (@last_month_revenue.to_f / 100.0) / current_tenant.square_footage.to_f

    @this_month_invoices = @invoices.select do |invoice|
      invoice.date > @this_month_start
    end
    
    @this_month_revenue = @this_month_invoices.sum {|invoice| invoice.amount_paid }
    @this_month_square_footage = (@this_month_revenue.to_f / 100.0) / current_tenant.square_footage.to_f
  end

  def expenses
    background_image
    @expenses = FeedItem.for_operator(current_tenant).expenses.order('created_at DESC').all
  end
end