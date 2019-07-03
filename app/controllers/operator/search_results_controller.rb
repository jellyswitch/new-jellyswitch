# typed: true
class Operator::SearchResultsController < Operator::BaseController
  before_action :background_image

  def new

  end

  def create
    @query = params[:query]
    turbolinks_redirect(query_search_results_path(query: @query), action: "replace")
  end

  def query
    @query = params[:query]
    @results = Searchkick.search(
      @query, 
      fields: [:text, :comments, :user_name, :type, :amount, :stripe_customer_id, :name, :email, :organization, :owner], 
      models: [FeedItem, User, Organization],
      operator: "or"
    )
    render :create, status: 200
  end
end