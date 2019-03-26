class Operator::SearchResultsController < Operator::BaseController
  before_action :background_image

  def new

  end

  def create
    @query = params[:query]
    @results = FeedItem.search(@query, fields: [:text, :user_name, :type, :amount])
    
  end
end