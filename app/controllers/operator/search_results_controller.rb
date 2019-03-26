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
    @results = FeedItem.search(@query, fields: [:text, :user_name, :type, :amount])
    render :create, status: 200
  end
end