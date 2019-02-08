class Operator::AccountingController < Operator::BaseController
  def index
    background_image
    @expenses = FeedItem.for_operator(current_tenant).expenses.order('created_at DESC').all
  end
end